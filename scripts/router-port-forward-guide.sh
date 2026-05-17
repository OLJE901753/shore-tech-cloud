#!/usr/bin/env bash
# Task 1.2: WAN/LAN port-forward mapping for your router admin UI.
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
LAN_IP="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}')"
LAN_IP="${SYNC_LAN_IP:-${LAN_IP:-$(hostname -I | awk '{print $1}')}}"
PUB_IP="$(curl -4 -s --max-time 10 ifconfig.me 2>/dev/null || echo unknown)"
DNS_IP="$(dig +short "${DOMAIN}" A @8.8.8.8 2>/dev/null | head -1 || true)"
DEFAULT_GW="$(ip route show default 2>/dev/null | awk '{print $3}' | head -1 || echo unknown)"
LAN_IFACE="$(ip -4 route show default 2>/dev/null | awk '{print $5; exit}')"
[[ -z "$LAN_IFACE" ]] && LAN_IFACE="$(ip -o -4 addr show up scope global | awk '{print $2; exit}')"

echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo "║  Shore Tech — Router port forwarding (copy into your router UI)              ║"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo ""
echo "Host (this PC)"
echo "  LAN IP:        ${LAN_IP}"
echo "  LAN interface: ${LAN_IFACE}"
echo "  Default GW:    ${DEFAULT_GW}  (usually your router)"
echo "  Public IP:     ${PUB_IP}"
echo "  DuckDNS:       ${DOMAIN} → ${DNS_IP:-lookup failed}"
echo ""

if [[ -n "${DNS_IP:-}" && "$PUB_IP" != unknown && "$DNS_IP" != "$PUB_IP" ]]; then
  echo "  WARN: DuckDNS A record (${DNS_IP}) ≠ current public IP (${PUB_IP})"
  echo "        Run: docker compose up -d --force-recreate duckdns"
  echo ""
fi

cat <<EOF
Create one "Virtual Server" / "Port Forward" / "NAT" rule per row:

┌──────────┬──────────┬─────────────────────┬──────────────┬──────────────┬─────────────────────────┐
│ WAN port │ Protocol │ Forward to LAN IP   │ LAN port     │ Service name │ Notes                   │
├──────────┼──────────┼─────────────────────┼──────────────┼──────────────┼─────────────────────────┤
│ 80       │ TCP      │ ${LAN_IP}           │ 80           │ npm-http     │ HTTP + Let's Encrypt    │
│ 443      │ TCP      │ ${LAN_IP}           │ 443          │ npm-https    │ HTTPS File Browser      │
│ 22000    │ TCP      │ ${LAN_IP}           │ 22000        │ syncthing    │ Device sync (internet)  │
│ 21027    │ UDP      │ ${LAN_IP}           │ 21027        │ syncthing-d  │ Local discovery         │
└──────────┴──────────┴─────────────────────┴──────────────┴──────────────┴─────────────────────────┘

Do NOT forward port 8384 (Syncthing GUI) or 81 (NPM admin) to the internet unless you add VPN/access controls.

Router checklist
  [ ] This PC uses a static/reserved DHCP lease at ${LAN_IP}
  [ ] Rules target ${LAN_IP}, not an old IP
  [ ] No duplicate forward on another device
  [ ] ISP does not use CGNAT (if it does, port forwards never work — use Cloudflare tunnel)
  [ ] After saving, test from mobile data: http://${DOMAIN}/

Verify
  ./scripts/verify-external-ports.sh
  ./scripts/check-external-access.sh
EOF
