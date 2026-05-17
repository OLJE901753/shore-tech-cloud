#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

DOMAIN="${DUCKDNS_SUBDOMAIN:-your-subdomain}.duckdns.org"
LAN_IP="$(hostname -I | awk '{print $1}')"
PUB_IP="$(curl -4 -s --max-time 10 ifconfig.me || echo unknown)"

echo "=== Shore Tech SSL / access check ==="
echo "Domain:     $DOMAIN"
echo "Public IP:  $PUB_IP"
echo "LAN IP:     $LAN_IP"
echo ""

echo "--- Local services ---"
curl -sf -o /dev/null http://127.0.0.1:81 && echo "OK   NPM admin (:81)" || echo "FAIL NPM admin (:81)"
curl -sf -o /dev/null http://127.0.0.1:8384 && echo "OK   Syncthing (:8384)" || echo "FAIL Syncthing"
CODE=$(curl -s -o /dev/null -w "%{http_code}" -H "Host: $DOMAIN" http://127.0.0.1:80/ || echo 000)
echo "     Proxy Host HTTP (via NPM): $CODE (404/200 OK; 502 = wrong forward scheme)"
echo ""

echo "--- DNS ---"
dig +short "$DOMAIN" A 2>/dev/null | head -1 | sed 's/^/A record: /' || echo "A record: (lookup failed)"
echo ""

echo "--- Internet → your domain (needs router port forward) ---"
EXT=$(curl -4 -s -o /dev/null -w "%{http_code}" --max-time 12 "http://$DOMAIN/" 2>/dev/null || true)
[[ -z "$EXT" ]] && EXT=000
if [[ "$EXT" == "000" ]]; then
  echo "FAIL http://$DOMAIN/ — timeout (forward TCP 80 → $LAN_IP on your router)"
elif [[ "$EXT" == "502" ]]; then
  echo "WARN http://$DOMAIN/ — 502 (NPM proxy misconfigured; use forward scheme http)"
else
  echo "OK   http://$DOMAIN/ — HTTP $EXT (Let's Encrypt HTTP challenge can work)"
fi

EXTS=$(curl -4 -s -o /dev/null -w "%{http_code}" --max-time 12 "https://$DOMAIN/" || echo 000)
if [[ "$EXTS" == "000" ]]; then
  echo "FAIL https://$DOMAIN/ — timeout (forward TCP 443 → $LAN_IP)"
else
  echo "     https://$DOMAIN/ — HTTP $EXTS"
fi

echo ""
if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx sync-cloudflared; then
  TUNNEL="$(docker logs sync-cloudflared 2>&1 | grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' | tail -1 || true)"
  [[ -n "$TUNNEL" ]] && echo "Cloudflare tunnel (works without port forward): ${TUNNEL}/login"
  echo ""
fi
echo "Router setup: ./scripts/router-port-forward-guide.sh"
echo "Host firewall: sudo ./scripts/configure-host-firewall.sh"
echo "External ports: ./scripts/verify-external-ports.sh"
echo "Fix all:        ./scripts/fix-external-access.sh"
echo "Interim tunnel: ./scripts/tunnel-fallback.sh start"
echo "Full URLs: ./scripts/show-access-urls.sh"

if [[ "${VERIFY_EXTERNAL_PORTS:-0}" == 1 ]]; then
  echo ""
  "$(dirname "${BASH_SOURCE[0]}")/verify-external-ports.sh" || true
fi
