#!/usr/bin/env bash
# Fix perimeter access: host ports → UPnP → verify → interim tunnel if still closed.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

DOMAIN="${DUCKDNS_SUBDOMAIN:-your-subdomain}.duckdns.org"

echo "=== Fix external access: ${DOMAIN} ==="
echo ""

echo "[1/5] Ensure Docker stack is up..."
docker compose up -d syncthing filebrowser nginx-proxy-manager duckdns
echo ""

echo "[2/5] Local listeners..."
if ! "$SCRIPT_DIR/verify-local-ports.sh"; then
  echo "ERROR: Start the stack first: docker compose up -d"
  exit 1
fi
echo ""

echo "[3/5] Host firewall (UFW)..."
if [[ "${EUID:-}" -eq 0 ]]; then
  "$SCRIPT_DIR/configure-host-firewall.sh"
elif command -v sudo >/dev/null 2>&1; then
  sudo "$SCRIPT_DIR/configure-host-firewall.sh" || echo "WARN: skipped UFW (sudo failed)"
else
  echo "WARN: run manually: sudo $SCRIPT_DIR/configure-host-firewall.sh"
fi
echo ""

echo "[4/5] Router (UPnP if available)..."
if command -v upnpc >/dev/null 2>&1; then
  "$SCRIPT_DIR/configure-router-upnp.sh" || true
else
  echo "  Install miniupnpc for automatic mapping: sudo apt install -y miniupnpc"
  echo "  Manual rules: $SCRIPT_DIR/router-port-forward-guide.sh"
fi
echo ""

echo "[5/5] External verification..."
if "$SCRIPT_DIR/verify-external-ports.sh"; then
  echo ""
  echo "SUCCESS: https://${DOMAIN}/ should work from the internet."
  if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx sync-cloudflared; then
    echo "Stopping interim tunnel (no longer needed)..."
    "$SCRIPT_DIR/tunnel-fallback.sh" stop || true
  fi
  exit 0
fi

echo ""
echo "Perimeter still closed — starting interim Cloudflare tunnel..."
"$SCRIPT_DIR/tunnel-fallback.sh" start || true
"$SCRIPT_DIR/tunnel-fallback.sh" status
echo ""
echo "Permanent fix: configure router (see table below), then re-run this script."
echo ""
"$SCRIPT_DIR/router-port-forward-guide.sh" | head -22
exit 1
