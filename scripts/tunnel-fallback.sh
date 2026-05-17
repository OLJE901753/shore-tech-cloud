#!/usr/bin/env bash
# Interim Cloudflare quick tunnel — not for production; use when router ports are closed.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
PROFILE="tunnel-fallback"

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi
export DUCKDNS_FQDN="${DUCKDNS_FQDN:-${DUCKDNS_SUBDOMAIN:-your-subdomain}.duckdns.org}"

wait_for_tunnel_url() {
  local max="${1:-45}" elapsed=0 url=""
  while (( elapsed < max )); do
    url="$(docker logs sync-cloudflared 2>&1 | grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' | tail -1 || true)"
    [[ -n "$url" ]] && { echo "$url"; return 0; }
    sleep 2
    elapsed=$((elapsed + 2))
  done
  return 1
}

save_tunnel_url() {
  local base="$1"
  mkdir -p .secrets
  umask 077
  printf '%s/login\n' "$base" > .secrets/tunnel-url.txt
  chmod 600 .secrets/tunnel-url.txt
}

cmd="${1:-status}"

case "$cmd" in
  start)
    docker compose --profile "$PROFILE" up -d --force-recreate cloudflared
    if TUNNEL="$(wait_for_tunnel_url 45)"; then
      save_tunnel_url "$TUNNEL"
      echo "Tunnel: ${TUNNEL}/login"
      echo "Saved:  ${ROOT}/.secrets/tunnel-url.txt"
    else
      echo "Tunnel still starting — run: $0 status"
    fi
    ;;
  stop)
    docker compose --profile "$PROFILE" stop cloudflared 2>/dev/null || true
    docker compose --profile "$PROFILE" rm -f cloudflared 2>/dev/null || true
    echo "Cloudflare quick tunnel stopped."
    ;;
  status)
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx sync-cloudflared; then
      TUNNEL="$(docker logs sync-cloudflared 2>&1 | grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' | tail -1 || true)"
      echo "tunnel-fallback: running"
      [[ -n "$TUNNEL" ]] && echo "  ${TUNNEL}/login"
    else
      echo "tunnel-fallback: stopped"
    fi
  ;;
  *)
    echo "Usage: $0 {start|stop|status}"
    exit 1
    ;;
esac
