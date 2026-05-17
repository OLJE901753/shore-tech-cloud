#!/usr/bin/env bash
# Run from ~/sync-server only. DNS challenge (no port 80 required).
set -euo pipefail
cd ~/sync-server
set -a
# shellcheck disable=SC1091
source .env
set +a
export DuckDNS_Token="$DUCKDNS_TOKEN"
mkdir -p config/ssl/acme
docker run --rm \
  -v "$(pwd)/config/ssl/acme:/acme.sh" \
  -e DuckDNS_Token \
  neilpang/acme.sh \
  --issue --dns dns_duckdns -d "${DUCKDNS_SUBDOMAIN}.duckdns.org" \
  --server letsencrypt --keylength 2048 --force --dnssleep 180
