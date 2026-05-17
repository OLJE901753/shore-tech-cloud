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

echo "=== Shore Tech access URLs ==="
echo ""
echo "LAN (same Wi-Fi):"
echo "  Syncthing GUI:  http://${LAN_IP}:8384"
echo "  NPM admin:      http://${LAN_IP}:81"
echo "  File Browser:   https://${DOMAIN}/  (after router forwards 443)"
echo ""
echo "DuckDNS (needs router TCP 80+443 → ${LAN_IP}):"
echo "  https://${DOMAIN}/"
echo ""

if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx sync-cloudflared; then
  # tunnel-fallback profile
  TUNNEL="$(docker logs sync-cloudflared 2>&1 | grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' | tail -1 || true)"
  if [[ -n "$TUNNEL" ]]; then
    echo "Cloudflare quick tunnel (no router ports required):"
    echo "  ${TUNNEL}/login"
    echo "  (URL changes if you recreate the container)"
    echo ""
  fi
fi

if [[ -f config/syncthing/config.xml ]]; then
  APIKEY="$(grep -oP '(?<=<apikey>)[^<]+' config/syncthing/config.xml | head -1)"
  DEVICE_ID="$(curl -sf -H "X-API-Key: $APIKEY" http://127.0.0.1:8384/rest/system/status | python3 -c "import sys,json; print(json.load(sys.stdin)['myID'])" 2>/dev/null || true)"
  if [[ -n "$DEVICE_ID" ]]; then
    echo "Syncthing (Android pairing):"
    echo "  Device ID: ${DEVICE_ID}"
    echo "  Shared folder path on host: ${ROOT}/data/shared"
    echo ""
  fi
fi

if [[ -f .secrets/tunnel-url.txt ]]; then
  echo "Interim tunnel URL: $(tr -d '\n' < .secrets/tunnel-url.txt)"
fi

if [[ -f .secrets/filebrowser-admin.txt ]]; then
  echo "File Browser credentials: ${ROOT}/.secrets/filebrowser-admin.txt"
fi
