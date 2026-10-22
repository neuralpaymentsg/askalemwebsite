#!/usr/bin/env bash
# Connect beta.askalem.com to the EXISTING Alem Agent Gateway container.
# No container images, databases, developers' source files or Katana modified.
set -Eeuo pipefail
C=/opt/app/docker/Caddyfile
B=/opt/app/backups/Caddyfile.beta-$(date -u +%Y%m%d-%H%M%S)
[ "$(id -u)" = 0 ] || { echo "Run with sudo"; exit 1; }
echo "Checking existing Alem Agent Gateway..."
docker ps --format '{{.Names}}' | grep -Fxq alem-agent-site || { echo "Container alem-agent-site is not running"; exit 1; }
docker exec docker-caddy-1 sh -c 'wget -qO- http://alem-agent-site:3000/app.html' | grep -q 'Control Tower' || { echo "Expected ROI/Control Tower app not found on upstream"; exit 1; }
docker exec docker-caddy-1 sh -c 'wget -qO- http://alem-agent-site:3000/health' > /dev/null || { echo "Gateway health failed"; exit 1; }
echo "Gateway verified. Preserving Caddy configuration..."
cp -p "$C" "$B"
restore(){
  cp -f "$B" "$C"
  docker restart docker-caddy-1 || true
}
trap 'restore' ERR
python3 - "$C" <<'PY'
import re,sys
from pathlib import Path
p=Path(sys.argv[1]);s=p.read_text()
m=re.search(r'(?m)^beta\.askalem\.com\s*\{',s)
if not m:raise SystemExit("beta host block missing")
d=0;end=None
for i in range(s.index("{",m.start()),len(s)):
 if s[i]=="{":d+=1
 elif s[i]=="}":
  d-=1
  if d==0:end=i+1;break
if end is None:raise SystemExit("Caddy braces mismatch")
block='''beta.askalem.com {
    encode gzip zstd
    header {
        X-Content-Type-Options nosniff
        Referrer-Policy strict-origin-when-cross-origin
        -Server
    }
    reverse_proxy alem-agent-site:3000
}'''
p.write_text(s[:m.start()]+block+s[end:])
PY
docker exec docker-caddy-1 caddy validate --config /etc/caddy/Caddyfile
docker restart docker-caddy-1
sleep 4
code=$(curl -sS --max-time 20 -o /dev/null -w '%{http_code}' https://beta.askalem.com/app.html)
echo "ROI app: HTTP $code"
[ "$code" = 200 ]
trap - ERR
echo "Beta routed to the existing alem-agent-site. Backup: $B"
echo "Important: verify login/registration; backend PUBLIC_BASE_URL may still refer to askalem.com."
