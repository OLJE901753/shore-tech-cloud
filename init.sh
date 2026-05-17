#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

if [[ ! -f .env ]]; then
  echo "ERROR: .env not found. Copy .env.example to .env and fill in your values:"
  echo "  cp .env.example .env"
  exit 1
fi

set -a
# shellcheck disable=SC1091
source .env
set +a

: "${PUID:?PUID must be set in .env}"
: "${PGID:?PGID must be set in .env}"

mkdir -p \
  config/syncthing \
  config/filebrowser \
  config/npm/data \
  config/npm/letsencrypt \
  config/duckdns \
  data \
  .secrets

chown -R "${PUID}:${PGID}" config data

if [[ ! -f config/filebrowser/filebrowser.db ]]; then
  echo "Initializing File Browser database..."
  docker run --rm \
    -u "${PUID}:${PGID}" \
    -v "${ROOT}/config/filebrowser:/config" \
    filebrowser/filebrowser:latest \
    config init -d /config/filebrowser.db
  chown -R "${PUID}:${PGID}" config/filebrowser
fi

FB_USER="${FILEBROWSER_ADMIN_USER:-admin}"
FB_PASS="${FILEBROWSER_ADMIN_PASSWORD:-}"

if [[ -n "$FB_PASS" ]]; then
  if docker compose ps filebrowser 2>/dev/null | grep -q 'Up'; then
    docker compose stop filebrowser
    RESTART_FB=1
  else
    RESTART_FB=0
  fi

  if ! docker run --rm -u "${PUID}:${PGID}" \
    -v "${ROOT}/config/filebrowser:/config" \
    --entrypoint /bin/filebrowser \
    filebrowser/filebrowser:latest \
    users ls -d /config/filebrowser.db 2>/dev/null | grep -q "$FB_USER"; then
    echo "Creating File Browser user: $FB_USER"
    docker run --rm -u "${PUID}:${PGID}" \
      -v "${ROOT}/config/filebrowser:/config" \
      --entrypoint /bin/filebrowser \
      filebrowser/filebrowser:latest \
      users add "$FB_USER" "$FB_PASS" \
      -d /config/filebrowser.db \
      --perm.admin
    umask 077
    printf 'File Browser\nUsername: %s\nPassword: (from .env FILEBROWSER_ADMIN_PASSWORD)\n' "$FB_USER" \
      > .secrets/filebrowser-admin.txt
    chmod 600 .secrets/filebrowser-admin.txt
  fi

  if [[ "${RESTART_FB:-0}" -eq 1 ]]; then
    docker compose start filebrowser
  fi
fi

echo ""
echo "Initialization complete."
echo ""
echo "Next steps:"
echo "  1. Confirm .env (DuckDNS token, subdomain, TZ)."
echo "  2. After editing .env:  docker compose up -d --force-recreate duckdns"
echo "  3. Start the stack:       docker compose up -d"
echo "  4. NPM admin:             http://<host-ip>:81"
echo "  5. Proxy host:            <subdomain>.duckdns.org -> filebrowser:80"
echo "  6. SSL:                   NPM proxy host -> SSL tab -> Request certificate"
echo "  7. Perimeter:             sudo ./scripts/configure-host-firewall.sh"
echo "                            ./scripts/router-port-forward-guide.sh"
echo "                            ./scripts/verify-external-ports.sh"
echo "  8. File Browser login:    set FILEBROWSER_ADMIN_PASSWORD in .env and re-run init.sh,"
echo "                            or: docker compose stop filebrowser && docker run --rm ..."
echo "  9. Syncthing Android:     pair at http://<host-ip>:8384"
