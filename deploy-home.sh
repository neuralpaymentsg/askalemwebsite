#!/usr/bin/env bash
# Update only the existing askalem.com static homepage; no service restart.
set -Eeuo pipefail
MODE=${1:---check}
REF=${2:-}
[[ "$MODE" == --check || "$MODE" == --apply ]] || { echo 'Use --check or --apply, followed by a full commit SHA.'; exit 2; }
[[ "$REF" =~ ^[0-9a-f]{40}$ ]] || { echo 'A full 40-character commit SHA is required.'; exit 2; }
[[ $(id -u) == 0 ]] || { echo 'Run with sudo.'; exit 2; }
SITE=/var/lib/docker/volumes/docker_caddy_data/_data/askalem-home
CONFIG=/opt/app/docker/Caddyfile
BASE=https://raw.githubusercontent.com/neuralpaymentsg/askalemwebsite/$REF
[[ -f "$SITE/index.html" && ! -L "$SITE/index.html" ]] || { echo 'Expected homepage not found.'; exit 1; }
grep -q 'root \* /data/askalem-home' "$CONFIG" || { echo 'Homepage root differs; review configuration first.'; exit 1; }
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
for file in index.html llms.txt; do
  curl -fsSL --connect-timeout 10 --max-time 45 "$BASE/$file" -o "$TMP/$file"
done
python3 - "$TMP" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]);h=(p/'index.html').read_text()
for expected in ['Infrastructure for ', 'agentic commerce.', 'https://finance.askalem.com/', 'https://app.finance.askalem.com/', 'Investors and programs', 'class="antler-logo"', 'Planned execution through payment partners']:
    if expected not in h: raise SystemExit('Missing expected homepage content: '+expected)
for removed in ['$17,500', 'Paying customers', 'B2B pilots across Alem', 'Antoine Fourmont-Fingal', 'and angel investors']:
    if removed in h: raise SystemExit('Removed traction content is still present: '+removed)
if len(h)<10000 or '</html>' not in h: raise SystemExit('Homepage download is incomplete')
if 'Infrastructure for agentic commerce' not in (p/'llms.txt').read_text(): raise SystemExit('Metadata mismatch')
PY
CONFIG_HASH=$(sha256sum "$CONFIG" | cut -d' ' -f1)
echo 'PREFLIGHT=PASS; target=askalem.com; files=index.html,llms.txt'
if [[ "$MODE" == --check ]]; then echo 'PRODUCTION_MODIFIED=NO'; exit 0; fi
mkdir -p /opt/app/backups
BACKUP=$(mktemp -d /opt/app/backups/alem-home-20261124-XXXXXX)
for file in index.html llms.txt; do
  if [[ -e "$SITE/$file" ]]; then cp -p "$SITE/$file" "$BACKUP/$file"; fi
done
rollback(){
  local result=$?
  trap - ERR
  for file in index.html llms.txt; do
    if [[ -f "$BACKUP/$file" ]]; then
      cp -p "$BACKUP/$file" "$SITE/.$file.rollback"
      mv -f "$SITE/.$file.rollback" "$SITE/$file"
    else
      rm -f "$SITE/$file"
    fi
  done
  echo "DEPLOY=ROLLED_BACK; backup=$BACKUP"
  exit "$result"
}
trap rollback ERR
for file in index.html llms.txt; do
  install -m 644 "$TMP/$file" "$SITE/.$file.new"
  mv -f "$SITE/.$file.new" "$SITE/$file"
done
[[ $(sha256sum "$CONFIG" | cut -d' ' -f1) == "$CONFIG_HASH" ]]
VERIFIED=no
for attempt in 1 2 3; do
  if curl -fsSL --connect-timeout 10 --max-time 30 "https://askalem.com/?release=$REF" -o "$TMP/live.html" && cmp -s "$TMP/index.html" "$TMP/live.html"; then VERIFIED=yes; break; fi
  sleep 2
done
[[ "$VERIFIED" == yes ]]
curl -fsSL --connect-timeout 10 --max-time 30 "https://askalem.com/llms.txt?release=$REF" -o "$TMP/live-llms.txt"
cmp -s "$TMP/llms.txt" "$TMP/live-llms.txt"
trap - ERR
echo "DEPLOY=PASS; backup=$BACKUP"
echo 'FINANCE_AND_GATEWAY_UNCHANGED=YES; CADDY_RESTARTED=NO'
