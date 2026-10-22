#!/usr/bin/env bash
# Configure Resend delivery for password recovery without exposing API keys in shell history.
set -Eeuo pipefail
NAME=alem-finance-v01-api-1
[ "$(id -u)" = 0 ] || { echo "Run using sudo"; exit 1; }
docker inspect "$NAME" >/dev/null
if [ ! -t 0 ]; then
  echo "Run this script interactively in SSH (not through a pipe)."
  exit 1
fi
echo "Alem Finance password recovery — email delivery"
echo "Use a Resend API key for a verified sending domain."
read -r -s -p "Resend API key (hidden input): " SECRET
echo
if [ "${#SECRET}" -lt 12 ]; then
  echo "Key is missing or too short; no changes made."
  exit 1
fi
read -r -p "Verified sender [Alem Finance <no-reply@notify.askalem.com>]: " SENDER
SENDER="${SENDER:-Alem Finance <no-reply@notify.askalem.com>}"
if [[ "$SENDER" != *"@"* ]]; then
  echo "Invalid sender; no changes made."
  exit 1
fi
echo "Saving credentials inside existing persistent Finance private-storage volume..."
printf '%s\n%s\n' "$SECRET" "$SENDER" | docker exec -i "$NAME" python -c '
import json,os,sys
from pathlib import Path
items=sys.stdin.read().splitlines()
if len(items)!=2 or not items[0]: raise SystemExit("Missing settings")
p=Path("/app/private_storage/password_reset_mail.json")
p.parent.mkdir(parents=True,exist_ok=True)
tmp=p.with_suffix(".tmp")
fd=os.open(str(tmp),os.O_WRONLY|os.O_CREAT|os.O_TRUNC,0o600)
with os.fdopen(fd,"w") as f:
 json.dump({"resend_api_key":items[0],"from_email":items[1]},f)
 f.write("\n")
os.replace(tmp,p)
os.chmod(p,0o600)
print("Mail configuration saved. Secret not printed.")
'
unset SECRET
echo "Email configuration saved. No restart needed."
echo "To send yourself a test recovery email, open:"
echo "https://app.finance.askalem.com/static/forgot-password.html"
echo "If email does not arrive, check Resend sender domain verification and Finance logs."
