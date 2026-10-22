#!/usr/bin/env bash
# Alem Finance only. Adds password recovery and UI; does not touch Katana, ROI or marketing sites.
set -Eeuo pipefail
NAME=alem-finance-v01-api-1
BASE=https://raw.githubusercontent.com/neuralpaymentsg/askalemwebsite/main/finance-recovery
TS=$(date -u +%Y%m%d-%H%M%S)
BACK=/home/dinara/alem-finance-recovery/backups/$TS
TEMP=$(mktemp -d)
trap 'rm -rf "$TEMP"' EXIT
[ "$(id -u)" = 0 ] || { echo "Run with sudo"; exit 1; }
docker inspect "$NAME" >/dev/null || { echo "Finance container missing"; exit 1; }
echo "=== Downloading add-on source ==="
for file in password_reset_feature.py forgot-password.html reset-password.html password-reset.js password-reset.css; do
  curl -fsSL --max-time 30 "$BASE/$file" -o "$TEMP/$file"
done
python3 -m py_compile "$TEMP/password_reset_feature.py"
echo "=== Backing up current files ==="
mkdir -p "$BACK"
docker cp "$NAME:/app/app/main.py" "$BACK/main.py"
docker cp "$NAME:/app/app/static/index.html" "$BACK/index.html"
test -s "$BACK/main.py"
test -s "$BACK/index.html"
if grep -q 'install_password_reset(app' "$BACK/main.py"; then
  echo "Password reset already installed. Refusing duplicate install."
  exit 1
fi
if ! grep -q 'id="auth-form"' "$BACK/index.html"; then
  echo "Expected auth form not found; not changing UI."
  exit 1
fi
if ! grep -q 'from app' "$BACK/main.py"; then
  echo "Unexpected app.main; refusing install."
  exit 1
fi
echo "=== Preparing additive source change ==="
cp "$BACK/main.py" "$TEMP/main.py"
cp "$BACK/index.html" "$TEMP/index.html"
python3 - "$TEMP/main.py" "$TEMP/index.html" <<'PY'
from pathlib import Path
import sys
backend=Path(sys.argv[1]); source=backend.read_text()
source += '\n\n# Alem Finance: optional, isolated password recovery routes\nfrom app.password_reset_feature import install_password_reset\ninstall_password_reset(app, get_db, User)\n'
backend.write_text(source)
front=Path(sys.argv[2]); html=front.read_text()
mark=html.index('id="auth-form"')
end=html.index('</form>',mark)+len('</form>')
addition='\n<div class="alem-recovery-link"><a href="/static/forgot-password.html">Forgot password?</a></div>\n'
html=html[:end]+addition+html[end:]
css='<link rel="stylesheet" href="/static/forgot-link.css">'
html=html.replace('</head>',css+'</head>',1)
front.write_text(html)
PY
python3 -m py_compile "$TEMP/main.py"
cat > "$TEMP/forgot-link.css" <<'CSS'
.alem-recovery-link{text-align:right;margin:12px 0 14px;font-size:13px;font-weight:650}
.alem-recovery-link a{color:#df7157;text-decoration:none}
.alem-recovery-link a:hover{text-decoration:underline}
CSS
restore(){
  echo "Rolling back current Finance container files"
  docker cp "$BACK/main.py" "$NAME:/app/app/main.py" || true
  docker cp "$BACK/index.html" "$NAME:/app/app/static/index.html" || true
  docker restart "$NAME" || true
}
trap 'restore' ERR
echo "=== Installing standalone recovery module and pages ==="
docker cp "$TEMP/password_reset_feature.py" "$NAME:/app/app/password_reset_feature.py"
docker cp "$TEMP/main.py" "$NAME:/app/app/main.py"
docker cp "$TEMP/index.html" "$NAME:/app/app/static/index.html"
for file in forgot-password.html reset-password.html password-reset.js password-reset.css forgot-link.css; do
  docker cp "$TEMP/$file" "$NAME:/app/app/static/$file"
done
docker exec "$NAME" python -m py_compile /app/app/main.py /app/app/password_reset_feature.py
echo "=== Restarting Finance only ==="
docker restart "$NAME"
sleep 4
echo "=== Verifying API and pages ==="
for url in \
  https://app.finance.askalem.com/api/health \
  https://app.finance.askalem.com/static/forgot-password.html \
  https://app.finance.askalem.com/static/reset-password.html \
  https://app.finance.askalem.com/static/password-reset.js \
  https://app.finance.askalem.com/static/password-reset.css; do
  code=$(curl -sSL --max-time 20 -o /dev/null -w '%{http_code}' "$url")
  echo "$url -> $code"
  [ "$code" = 200 ]
done
curl -fsSL --max-time 15 https://app.finance.askalem.com/openapi.json | python3 -c '
import sys,json
d=json.load(sys.stdin)
assert "/api/auth/forgot-password" in d["paths"]
assert "/api/auth/reset-password" in d["paths"]
print("Both recovery endpoints active")
'
untrusted=$(curl -sSL -o /dev/null -w '%{http_code}' --max-time 10 -X POST \
  https://app.finance.askalem.com/api/auth/reset-password \
  -H 'Origin: https://untrusted.example' -H 'Content-Type: application/json' -d '{}')
[ "$untrusted" = 403 ] || { echo "Untrusted origin returned $untrusted, expected 403"; exit 1; }
echo "=== Saving patched version as a local Docker image ==="
oldimage=$(docker inspect "$NAME" --format '{{.Config.Image}}')
docker image tag "$oldimage" "alem-finance-v01-api:before-recovery-$TS"
docker commit --pause=true "$NAME" "$oldimage" >/dev/null
trap - ERR
echo "SUCCESS. Password recovery routes and forms installed."
echo "Backup: $BACK"
echo "Rebuilt image tag: $oldimage"
echo "Next: configure email delivery using configure-email.sh"
echo "NOTE: Future docker compose up --build will require source changes in the build context."
