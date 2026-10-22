#!/usr/bin/env bash
# Share existing Alem Resend delivery with Finance.
# Secret streamed through a pipe; never displayed, logged, or committed.
set -Eeuo pipefail
umask 077
FINANCE=alem-finance-v01-api-1
REPO=https://raw.githubusercontent.com/neuralpaymentsg/askalemwebsite/main
ROOT=/var/lib/docker/volumes/docker_caddy_data/_data/askalem-home
[ "$(id -u)" -eq 0 ] || { echo "Run with sudo bash"; exit 1; }
docker inspect "$FINANCE" >/dev/null
docker exec "$FINANCE" test -d /app/private_storage
source_name=""
for candidate in alem-agent-site alem-beta; do
  if docker inspect "$candidate" >/dev/null 2>&1 && \
     docker exec "$candidate" sh -c '
        [ -n "\${RESEND_API_KEY:-}" ] && exit 0
        for f in /run/secrets/resend-api-key /run/secrets/resend_api_key /run/secrets/askalem-beta-resend-api-key; do
          [ -s "$f" ] && exit 0
        done
        exit 1
     ' >/dev/null 2>&1; then
    source_name="$candidate"
    break
  fi
done

if [ -z "$source_name" ]; then
  echo "Resend secret not in ROI or beta container env / known mounted paths."
  echo "No changes made. It may be provided by Google Cloud Secret Manager."
  exit 2
fi
echo "Existing Resend configuration found in $source_name (key hidden)."

echo "Checking Finance recovery endpoints..."
if ! curl -fsSL --max-time 15 https://app.finance.askalem.com/openapi.json | \
  python3 -c 'import sys,json;p=json.load(sys.stdin)["paths"];assert "/api/auth/forgot-password" in p and "/api/auth/reset-password" in p'; then
  echo "Installing Finance recovery add-on..."
  TEMP="$(mktemp)"
  trap 'rm -f "$TEMP"' EXIT
  curl -fsSL --max-time 25 "$REPO/finance-recovery/install.sh" -o "$TEMP"
  bash "$TEMP"
fi

echo "Reusing sender and secret from $source_name..."
docker exec "$source_name" sh -c '
set -eu
KEY="\${RESEND_API_KEY:-}"
if [ -z "$KEY" ]; then
 for f in /run/secrets/resend-api-key /run/secrets/resend_api_key /run/secrets/askalem-beta-resend-api-key; do
  if [ -s "$f" ]; then KEY="$(cat "$f")"; break; fi
 done
fi
test -n "$KEY"
SENDER="\${EMAIL_FROM:-Alem <no-reply@notify.askalem.com>}"
printf "%s\n%s\n" "$KEY" "$SENDER"
' | docker exec -i "$FINANCE" python -c '
import json,os,sys
from pathlib import Path
data=sys.stdin.read().splitlines()
if len(data)!=2 or not data[0] or "@" not in data[1]:
 raise SystemExit("Incomplete Resend configuration")
p=Path("/app/private_storage/password_reset_mail.json")
p.parent.mkdir(parents=True,exist_ok=True)
tmp=p.with_suffix(".tmp")
fd=os.open(str(tmp),os.O_WRONLY|os.O_CREAT|os.O_TRUNC,0o600)
with os.fdopen(fd,"w") as f:
 json.dump({"resend_api_key":data[0],"from_email":data[1]},f)
 f.write("\n")
os.replace(tmp,p)
os.chmod(p,0o600)
print("Finance email credentials configured (secret hidden).")
'
echo "Installing shared password-recovery entry page..."
curl -fsSL --max-time 20 "$REPO/forgot-password.html" -o "$ROOT/forgot-password.html.tmp"
chmod 644 "$ROOT/forgot-password.html.tmp"
mv -f "$ROOT/forgot-password.html.tmp" "$ROOT/forgot-password.html"

echo "Verifying public pages..."
for url in \
  https://askalem.com/forgot-password.html \
  https://app.finance.askalem.com/static/forgot-password.html \
  https://beta.askalem.com/forgot-password; do
  code="$(curl -sSL --max-time 15 -o /dev/null -w '%{http_code}' "$url")"
  echo "$url -> HTTP $code"
  [ "$code" = 200 ] || exit 1
done
echo "Ready for a real recovery email test."
echo "NOTE: ROI PUBLIC_BASE_URL is still askalem.com and must be updated in its container deployment config."
