#!/usr/bin/env bash
# Let's Encrypt via DNS-01 (DuckDNS). Works without port 80, but DuckDNS TXT/CAA can be flaky.
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

: "${DUCKDNS_TOKEN:?Set DUCKDNS_TOKEN in .env}"
: "${DUCKDNS_SUBDOMAIN:?Set DUCKDNS_SUBDOMAIN in .env}"

DOMAIN="${DUCKDNS_SUBDOMAIN}.duckdns.org"
EMAIL="${SSL_EMAIL:-oliver.jensen@shoretech.no}"
mkdir -p config/ssl/acme config/ssl/certs

export DuckDNS_Token="$DUCKDNS_TOKEN"

echo "Issuing certificate for $DOMAIN (DNS challenge, dnssleep 120s)..."
docker run --rm \
  -v "$(pwd)/config/ssl/acme:/acme.sh" \
  -e DuckDNS_Token \
  neilpang/acme.sh \
  --register-account -m "$EMAIL" --server letsencrypt 2>/dev/null || true

docker run --rm \
  -v "$(pwd)/config/ssl/acme:/acme.sh" \
  -e DuckDNS_Token \
  neilpang/acme.sh \
  --issue --dns dns_duckdns -d "$DOMAIN" \
  --server letsencrypt --keylength 2048 --force --dnssleep 120

docker run --rm \
  -v "$(pwd)/config/ssl/acme:/acme.sh" \
  -v "$(pwd)/config/ssl/certs:/certs" \
  neilpang/acme.sh \
  --install-cert -d "$DOMAIN" \
  --key-file "/certs/${DOMAIN}.key" \
  --fullchain-file "/certs/${DOMAIN}.crt" \
  --reloadcmd "echo cert installed"

echo ""
echo "Certificate files:"
echo "  config/ssl/certs/${DOMAIN}.crt"
echo "  config/ssl/certs/${DOMAIN}.key"
echo ""
echo "NPM: SSL Certificates → Add → Custom → paste fullchain + privkey, then assign to proxy host."
