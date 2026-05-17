#!/usr/bin/env bash
# Task 1.1: Align Ubuntu UFW with sync stack ports and verify local listeners.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ "${EUID:-}" -ne 0 ]]; then
  exec sudo -E bash "$0" "$@"
fi

if ! command -v ufw >/dev/null 2>&1; then
  echo "ERROR: ufw not installed. Install with: sudo apt install ufw"
  exit 1
fi

ENABLE_UFW=false
for arg in "$@"; do
  case "$arg" in
    --enable) ENABLE_UFW=true ;;
    -h|--help)
      echo "Usage: $0 [--enable]"
      echo "  Opens ports 80, 443, 22000/tcp, 21027/udp for NPM + Syncthing."
      echo "  --enable  Also runs 'ufw enable' (default incoming policy should be reviewed first)."
      exit 0
      ;;
  esac
done

echo "=== Shore Tech host firewall (UFW) ==="
echo ""

ENABLED="$(grep -E '^ENABLED=' /etc/ufw/ufw.conf | cut -d= -f2)"
echo "UFW status: $(ufw status | head -1)"
echo "UFW config ENABLED=${ENABLED}"
echo ""

open_port() {
  local spec="$1"
  local comment="$2"
  if ufw status numbered 2>/dev/null | grep -qF "$spec"; then
    echo "  skip  $spec (rule exists)"
  else
    ufw allow "$spec" comment "$comment"
    echo "  added $spec — $comment"
  fi
}

echo "Adding allow rules (persist even when UFW is inactive):"
open_port "80/tcp" "NPM HTTP"
open_port "443/tcp" "NPM HTTPS"
open_port "22000/tcp" "Syncthing Sync"
open_port "21027/udp" "Syncthing Discovery"
echo ""

if [[ "$ENABLE_UFW" == true ]]; then
  echo "Enabling UFW..."
  ufw --force enable
else
  if [[ "$ENABLED" == "no" ]]; then
    echo "UFW is disabled — incoming traffic is NOT blocked by the host firewall."
    echo "Perimeter timeouts are almost certainly router/ISP, not UFW."
    echo "To enable UFW with these rules: sudo $0 --enable"
  fi
fi

echo ""
"$(dirname "${BASH_SOURCE[0]}")/verify-local-ports.sh"

echo ""
echo "Done. Next: ./scripts/fix-external-access.sh or ./scripts/router-port-forward-guide.sh"
