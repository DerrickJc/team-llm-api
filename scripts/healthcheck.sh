#!/usr/bin/env bash

set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "${SCRIPT_DIR}/lib.sh"

wait_mode=false
if [[ "${1:-}" == "--wait" ]]; then
  wait_mode=true
elif [[ $# -gt 0 ]]; then
  die "usage: ./scripts/healthcheck.sh [--wait]"
fi

require_command docker
require_runtime_config

services=(postgres redis cpa new-api nginx)
attempts=1
if [[ "$wait_mode" == true ]]; then
  attempts=36
fi

check_once() {
  local service container state health
  for service in "${services[@]}"; do
    container="$(compose ps -q "$service")"
    [[ -n "$container" ]] || return 1
    state="$(docker inspect --format '{{.State.Status}}' "$container")"
    [[ "$state" == "running" ]] || return 1
    health="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$container")"
    [[ "$health" == "healthy" || "$health" == "none" ]] || return 1
  done
}

for ((attempt = 1; attempt <= attempts; attempt++)); do
  if check_once; then
    break
  fi
  if (( attempt == attempts )); then
    compose ps
    die "services did not become healthy"
  fi
  sleep 5
done

cpa_api_key="$(env_value CPA_API_KEY)"
compose exec -T new-api sh -ec \
  'wget -qO- --header="Authorization: Bearer $1" http://cpa:8317/v1/models >/dev/null' \
  sh "$cpa_api_key"

if [[ "${PUBLIC_CHECK:-1}" == "1" ]]; then
  require_command curl
  domain="$(env_value DOMAIN)"
  curl --fail --silent --show-error --max-time 20 \
    "https://${domain}/api/status" | grep -Eq '"success"[[:space:]]*:[[:space:]]*true' || \
    die "public New API status check failed; verify DNS, Cloudflare proxy, Full (strict), and AOP"
fi

log "all services and the CPA route are healthy"
