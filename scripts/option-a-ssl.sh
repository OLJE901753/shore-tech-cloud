#!/usr/bin/env bash
# Option A: Let's Encrypt via HTTP-01 (router ports 80 + 443 forwarded).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ ! -f .env ]]; then
  echo "ERROR: .env missing"
  exit 1
fi

set -a
# shellcheck disable=SC1091
source .env
set +a

DOMAIN="${DUCKDNS_SUBDOMAIN}.duckdns.org"
EMAIL="${SSL_EMAIL:-oliver.jensen@shoretech.no}"
LAN_IP="$(hostname -I | awk '{print $1}')"
MAX_WAIT="${1:-600}"   # seconds to wait for port 80 (default 10 min)
POLL=15

echo "=============================================="
echo " Option A: Let's Encrypt (HTTP-01)"
echo "=============================================="
echo ""
echo "1) On your ROUTER, create port forwards:"
echo "     TCP 80  -> ${LAN_IP}"
echo "     TCP 443 -> ${LAN_IP}"
echo ""
echo "2) Test from your PHONE (mobile data, not Wi-Fi):"
echo "     http://${DOMAIN}/"
echo ""
echo "Waiting up to ${MAX_WAIT}s for internet access to port 80..."
echo ""

ensure_acme_nginx() {
  "$(dirname "${BASH_SOURCE[0]}")/enable-acme-nginx.sh"
}

wait_for_port80() {
  local elapsed=0
  while (( elapsed < MAX_WAIT )); do
    CODE=$(curl -4 -s -o /dev/null -w "%{http_code}" --max-time 12 "http://${DOMAIN}/.well-known/acme-challenge/ping" 2>/dev/null || true)
    [[ -z "$CODE" ]] && CODE=000
    if [[ "$CODE" != "000" ]]; then
      echo "OK   Port 80 reachable (HTTP ${CODE} on ACME path)"
      return 0
    fi
    echo "     Still waiting... (${elapsed}s / ${MAX_WAIT}s)"
    sleep "$POLL"
    elapsed=$((elapsed + POLL))
  done
  return 1
}

ensure_acme_nginx
docker exec sync-npm sh -c 'echo ping > /data/letsencrypt-acme-challenge/.well-known/acme-challenge/ping'

if ! wait_for_port80; then
  echo ""
  echo "FAIL: Port 80 is not reachable from the internet yet."
  echo "Configure router forwards, then run again:"
  echo "  ./scripts/option-a-ssl.sh"
  exit 1
fi

echo ""
echo "Requesting certificate via certbot (inside NPM container)..."
CERT_NAME="npm-shoretech-$(date +%s)"

if ! docker exec sync-npm certbot certonly \
  --config /etc/letsencrypt.ini \
  --work-dir /tmp/letsencrypt-lib \
  --logs-dir /data/logs \
  --cert-name "$CERT_NAME" \
  --agree-tos \
  --authenticator webroot \
  -m "$EMAIL" \
  --preferred-challenges http \
  --domains "$DOMAIN" \
  --non-interactive; then
  echo ""
  echo "Certbot failed. Try NPM UI: Hosts -> Proxy Host -> SSL -> Request certificate"
  exit 1
fi

LIVE="/etc/letsencrypt/live/${CERT_NAME}"
echo ""
echo "SUCCESS: Certificate issued at ${LIVE}"
echo ""
echo "Finish in NPM (http://${LAN_IP}:81):"
echo "  1. SSL Certificates -> Add -> Custom"
echo "  2. Certificate: paste  ${LIVE}/fullchain.pem"
echo "     Key: paste         ${LIVE}/privkey.pem"
echo "     (docker exec sync-npm cat ${LIVE}/fullchain.pem)"
echo "  3. Edit proxy host ${DOMAIN} -> SSL -> select cert -> Force SSL -> Save"
echo ""
echo "Or request the same cert in NPM UI now (should succeed with ports open)."
