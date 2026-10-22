#!/usr/bin/env bash
set -Eeuo pipefail
BASE=https://raw.githubusercontent.com/neuralpaymentsg/askalemwebsite/main
C=/opt/app/docker/Caddyfile
V=/var/lib/docker/volumes/docker_caddy_data/_data
HOME_SITE=$V/askalem-home
FINANCE_SITE=$V/finance-landing
B=/opt/app/backups/alem-web-$(date -u +%Y%m%d-%H%M%S)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
[ "$(id -u)" = 0 ] || { echo "Run using sudo"; exit 1; }
grep -q '^app.finance.askalem.com {' "$C" || { echo "Missing protected finance app domain"; exit 1; }
grep -q 'root \* /data/askalem-home' "$C" || { echo "Main Caddy root mismatch"; exit 1; }
[ "$(curl -sS -o /dev/null -w '%{http_code}' http://127.0.0.1:18765/api/invoices)" = 401 ] || { echo "Finance auth guard failed"; exit 1; }
for x in index.html finance/index.html robots.txt sitemap.xml llms.txt; do
  mkdir -p "$T/$(dirname "$x")"
  curl -fsSL --max-time 30 "$BASE/$x" -o "$T/$x"
done
grep -q 'The Economic Control Plane' "$T/index.html"
grep -q 'Stop chasing invoices' "$T/finance/index.html"
mkdir -p "$B" "$HOME_SITE" "$FINANCE_SITE"
cp -p "$C" "$B/Caddyfile"
[ ! -e "$HOME_SITE/index.html" ] || cp -p "$HOME_SITE/index.html" "$B/old-home.html"
[ ! -e "$FINANCE_SITE/index.html" ] || cp -p "$FINANCE_SITE/index.html" "$B/old-finance.html"
restore(){
  echo "Rolling back..."
  cp -f "$B/Caddyfile" "$C"
  [ ! -e "$B/old-home.html" ] || cp -f "$B/old-home.html" "$HOME_SITE/index.html"
  [ ! -e "$B/old-finance.html" ] || cp -f "$B/old-finance.html" "$FINANCE_SITE/index.html"
  docker restart docker-caddy-1 || true
}
trap 'restore' ERR
install -m 644 "$T/index.html" "$HOME_SITE/index.html"
install -m 644 "$T/finance/index.html" "$FINANCE_SITE/index.html"
install -m 644 "$T/robots.txt" "$HOME_SITE/robots.txt"
install -m 644 "$T/sitemap.xml" "$HOME_SITE/sitemap.xml"
install -m 644 "$T/llms.txt" "$HOME_SITE/llms.txt"
python3 - "$C" <<'PY'
import re,sys
from pathlib import Path
p=Path(sys.argv[1]); s=p.read_text()
m=re.search(r'(?m)^finance\.askalem\.com\s*\{',s)
if not m: raise SystemExit("Finance domain block missing")
d=0; e=None
for i in range(s.index("{",m.start()),len(s)):
 if s[i]=="{":d+=1
 if s[i]=="}":
  d-=1
  if d==0:e=i+1;break
if e is None: raise SystemExit("Bad Caddy braces")
block='''finance.askalem.com {
    encode gzip zstd
    header {
        X-Content-Type-Options nosniff
        Referrer-Policy strict-origin-when-cross-origin
        -Server
    }
    root * /data/finance-landing
    file_server
}'''
p.write_text(s[:m.start()]+block+s[e:])
PY
docker exec docker-caddy-1 caddy validate --config /etc/caddy/Caddyfile
docker restart docker-caddy-1
sleep 4
for url in https://askalem.com/ https://finance.askalem.com/ https://app.finance.askalem.com/api/health; do
  code=$(curl -sSL --max-time 20 -o /dev/null -w '%{http_code}' "$url")
  echo "$url -> HTTP $code"
  [ "$code" = 200 ]
done
trap - ERR
echo "Published. Backups at $B. Finance API, ROI and Katana not modified."
