#!/usr/bin/env bash
# Attempt automatic WAN port forwards via UPnP (if the router supports IGD).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

LAN_IP="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}')"
LAN_IP="${SYNC_LAN_IP:-${LAN_IP:-$(hostname -I | awk '{print $1}')}}"

if ! command -v upnpc >/dev/null 2>&1; then
  echo "upnpc not installed."
  echo "Install:  sudo apt install -y miniupnpc"
  echo "Then run:  $0"
  exit 1
fi

echo "=== UPnP port mapping → ${LAN_IP} ==="
echo ""

if ! upnpc -s 2>&1 | head -5; then
  echo ""
  echo "WARN: Could not query UPnP gateway (disabled on router or blocked)."
  exit 1
fi

echo ""
map_port() {
  local ext="$1" int="$2" proto="$3" desc="$4"
  if upnpc -a "$LAN_IP" "$int" "$ext" "$proto" >/dev/null 2>&1; then
    echo "OK   ${proto} ${ext} → ${LAN_IP}:${int} (${desc})"
  else
    echo "FAIL ${proto} ${ext} → ${LAN_IP}:${int} (${desc})"
    return 1
  fi
}

fail=0
map_port 80 80 TCP "NPM HTTP" || fail=1
map_port 443 443 TCP "NPM HTTPS" || fail=1
map_port 22000 22000 TCP "Syncthing" || fail=1
map_port 21027 21027 UDP "Syncthing discovery" || fail=1

echo ""
if [[ $fail -eq 0 ]]; then
  echo "UPnP mappings added. Wait 10s, then: ./scripts/verify-external-ports.sh"
else
  echo "Some mappings failed — configure manually: ./scripts/router-port-forward-guide.sh"
fi
exit "$fail"
