#!/usr/bin/env bash
# Ensure proxy host serves /.well-known/acme-challenge/ for Let's Encrypt HTTP-01.
set -euo pipefail

docker exec sync-npm sh -c '
mkdir -p /data/letsencrypt-acme-challenge/.well-known/acme-challenge
for f in /data/nginx/proxy_host/*.conf; do
  [ -f "$f" ] || continue
  if grep -q "letsencrypt-acme-challenge.conf" "$f"; then
    continue
  fi
  sed -i "/location \/ {/i\\
  include conf.d/include/letsencrypt-acme-challenge.conf;\\
" "$f"
done
rm -f /data/nginx/custom/server_proxy.conf
nginx -t && nginx -s reload
'
echo "ACME challenge routing enabled on proxy hosts."
