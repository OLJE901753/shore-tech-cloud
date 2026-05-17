#!/usr/bin/env bash
# Interim HTTPS for LAN testing until Let's Encrypt works (browser will warn).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

DOMAIN="${DUCKDNS_SUBDOMAIN:-shoretech}.duckdns.org"
DIR="config/ssl/selfsigned"
mkdir -p "$DIR"

openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout "$DIR/privkey.pem" \
  -out "$DIR/fullchain.pem" \
  -subj "/CN=${DOMAIN}" 2>/dev/null

chmod 600 "$DIR/privkey.pem"
echo "Created self-signed cert in $DIR/"
echo "NPM → SSL Certificates → Add → Custom:"
echo "  Certificate: $ROOT/$DIR/fullchain.pem"
echo "  Key:         $ROOT/$DIR/privkey.pem"
echo "Then edit proxy host → SSL → select this certificate → Force SSL."
