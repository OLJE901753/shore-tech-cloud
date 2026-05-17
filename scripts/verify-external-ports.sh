#!/usr/bin/env bash
# Task 2.1: External port reachability via check-host.net (independent of local curl).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

DOMAIN="${DUCKDNS_SUBDOMAIN:-your-subdomain}.duckdns.org"
TARGET="${EXTERNAL_CHECK_HOST:-}"
if [[ -z "$TARGET" ]]; then
  TARGET="$(dig +short "$DOMAIN" A @8.8.8.8 2>/dev/null | head -1 || true)"
fi
if [[ -z "$TARGET" ]]; then
  TARGET="$(curl -4 -s --max-time 10 ifconfig.me 2>/dev/null || true)"
fi
if [[ -z "$TARGET" ]]; then
  echo "ERROR: Could not resolve check target (set EXTERNAL_CHECK_HOST or fix DuckDNS)"
  exit 1
fi

MAX_NODES="${EXTERNAL_CHECK_NODES:-4}"
POLL_SECS="${EXTERNAL_CHECK_POLL:-12}"
POLL_INTERVAL=2

# port:proto entries
PORTS=(80:tcp 443:tcp 22000:tcp)

check_port() {
  local port="$1" proto="$2"
  local endpoint check_id result_url elapsed=0

  if [[ "$proto" == "tcp" ]]; then
    endpoint="check-tcp"
  else
    endpoint="check-udp"
  fi

  check_id="$(curl -4 -s -H "Accept: application/json" \
    "https://check-host.net/${endpoint}?host=${TARGET}&port=${port}&max_nodes=${MAX_NODES}" \
    | python3 -c "import sys,json; print(json.load(sys.stdin).get('request_id',''))" 2>/dev/null || true)"

  if [[ -z "$check_id" ]]; then
    echo "FAIL ${proto}/${port} — could not start remote check"
    return 1
  fi

  result_url="https://check-host.net/check-result/${check_id}"
  local result=""
  while (( elapsed < POLL_SECS )); do
    sleep "$POLL_INTERVAL"
    elapsed=$((elapsed + POLL_INTERVAL))
    result="$(curl -4 -s -H "Accept: application/json" "$result_url" 2>/dev/null || true)"
  done

  local status
  status="$(CHECK_RESULT="$result" python3 <<'PY'
import json, os
raw = os.environ.get("CHECK_RESULT", "")
if not raw or raw == "null":
    print("pending")
    raise SystemExit(0)
data = json.loads(raw)
ok = fail = 0
for node, entries in data.items():
    if not entries:
        fail += 1
        continue
    e = entries[0]
    if not isinstance(e, dict):
        fail += 1
        continue
    if "error" in e:
        fail += 1
    elif "time" in e or "address" in e:
        ok += 1
    else:
        fail += 1
if ok and not fail:
    print("open")
elif ok:
    print("partial")
else:
    print("closed")
PY
)" || status="error"

  case "$status" in
    open)
      echo "OK   ${proto}/${port} reachable from internet (${TARGET})"
      return 0
      ;;
    partial)
      echo "WARN ${proto}/${port} reachable from some nodes only (${TARGET})"
      return 0
      ;;
    pending)
      echo "WARN ${proto}/${port} check still pending — retry or open ${result_url}"
      return 2
      ;;
    *)
      echo "FAIL ${proto}/${port} not reachable (${TARGET}) — forward on router"
      return 1
      ;;
  esac
}

fail=0
echo "=== External port verification (check-host.net) ==="
echo "Target: ${TARGET}  (${DOMAIN})"
echo "Nodes:  ${MAX_NODES}   Poll: ${POLL_SECS}s"
echo ""

for entry in "${PORTS[@]}"; do
  port="${entry%%:*}"
  proto="${entry##*:}"
  check_port "$port" "$proto" || fail=1
done

echo ""
if [[ $fail -eq 0 ]]; then
  echo "Perimeter ports look open. Test HTTPS: https://${DOMAIN}/"
  echo "Optional: stop interim tunnel — ./scripts/tunnel-fallback.sh stop"
else
  echo "Perimeter still closed. Configure router: ./scripts/router-port-forward-guide.sh"
  echo "Interim access: ./scripts/tunnel-fallback.sh start"
fi

exit "$fail"
