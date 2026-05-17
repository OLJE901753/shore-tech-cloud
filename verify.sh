#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

fail=0

check() {
  local name="$1"
  shift
  if "$@"; then
    echo "OK   $name"
  else
    echo "FAIL $name"
    fail=1
  fi
}

echo "=== Sync stack verification ==="
echo ""

check "docker compose ps (all running)" bash -c \
  'docker compose ps --status running 2>/dev/null | grep -q syncthing && \
   docker compose ps --status running 2>/dev/null | grep -q filebrowser && \
   docker compose ps --status running 2>/dev/null | grep -q nginx-proxy-manager && \
   docker compose ps --status running 2>/dev/null | grep -q duckdns'

check "Syncthing GUI (8384)" curl -sf -o /dev/null http://127.0.0.1:8384
check "NPM admin UI (81)" curl -sf -o /dev/null http://127.0.0.1:81

if docker compose exec -T filebrowser wget -qO- http://127.0.0.1:80 >/dev/null 2>&1; then
  echo "OK   File Browser internal HTTP"
else
  echo "FAIL File Browser internal HTTP"
  fail=1
fi

if docker compose logs duckdns --tail 30 2>&1 | grep -qiE 'error|invalid|failed'; then
  echo "WARN DuckDNS logs contain errors (check DUCKDNS_TOKEN in .env)"
else
  echo "OK   DuckDNS logs (no obvious errors)"
fi

echo "sync-verify-$(date +%s)" > data/.verify
check "shared data volume write" test -f data/.verify

echo ""
if [[ $fail -eq 0 ]]; then
  echo "All critical checks passed."
else
  echo "One or more checks failed."
  exit 1
fi
