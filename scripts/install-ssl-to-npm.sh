#!/usr/bin/env bash
# Install acme.sh certs from config/ssl/acme into NPM (after DNS issue succeeds).
set -euo pipefail
cd ~/sync-server
set -a
# shellcheck disable=SC1091
source .env
set +a

DOMAIN="${DUCKDNS_SUBDOMAIN}.duckdns.org"
ACME_DIR="config/ssl/acme/${DOMAIN}"
if [[ ! -f "$ACME_DIR/fullchain.cer" ]]; then
  echo "ERROR: Run DNS issue first. Missing $ACME_DIR/fullchain.cer"
  exit 1
fi

CERT_ID=$(docker run --rm \
  -v "$(pwd)/config/npm/data:/data" \
  -v "$(pwd)/scripts:/scripts:ro" \
  -e DOMAIN="$DOMAIN" \
  python:3.12-alpine python /scripts/_npm_install_cert.py | sed -n 's/certificate_id=//p')

docker run --rm \
  -v "$(pwd)/config/ssl/acme/${DOMAIN}:/src:ro" \
  -v "$(pwd)/config/npm/data:/data" \
  alpine:3.20 sh -c "
    mkdir -p /data/custom_ssl/npm-${CERT_ID}
    cp /src/fullchain.cer /data/custom_ssl/npm-${CERT_ID}/fullchain.pem
    cp /src/${DOMAIN}.key /data/custom_ssl/npm-${CERT_ID}/privkey.pem
    chmod 644 /data/custom_ssl/npm-${CERT_ID}/fullchain.pem
    chmod 600 /data/custom_ssl/npm-${CERT_ID}/privkey.pem
  "

echo "Regenerating nginx SSL config for certificate npm-${CERT_ID}..."
docker exec sync-npm sh -c "nginx -t && nginx -s reload" 2>/dev/null || docker compose restart nginx-proxy-manager
echo "If HTTPS fails, open NPM and re-save the proxy host once."
echo ""
echo "Done. Test: curl -kI https://127.0.0.1/ -H 'Host: ${DOMAIN}'"
echo "Public HTTPS needs router TCP 443 -> $(hostname -I | awk '{print $1}')"
