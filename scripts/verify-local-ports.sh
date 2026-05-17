#!/usr/bin/env bash
set -euo pipefail

check_listen() {
  local port="$1" proto="${2:-tcp}"
  local ss_args=(-l -n)
  [[ "$proto" == "tcp" ]] && ss_args=(-t -l -n) || ss_args=(-u -l -n)

  if ss "${ss_args[@]}" 2>/dev/null | grep -qE ":${port}\b"; then
    local bind
    bind="$(ss "${ss_args[@]}" 2>/dev/null | awk -v p=":${port}" '$4 ~ p {print $4; exit}')"
    if [[ "$bind" == *"0.0.0.0"* ]] || [[ "$bind" == *"[::]"* ]] || [[ "$bind" == *"*"* ]]; then
      echo "OK   ${proto}/${port} listening ($bind)"
      return 0
    fi
    echo "WARN ${proto}/${port} listening only on $bind"
    return 2
  fi
  echo "FAIL ${proto}/${port} not listening (run: docker compose up -d)"
  return 1
}

fail=0
echo "--- Local port bindings ---"
check_listen 80 tcp || fail=1
check_listen 443 tcp || fail=1
check_listen 22000 tcp || fail=1
check_listen 21027 udp || fail=1
exit "$fail"
