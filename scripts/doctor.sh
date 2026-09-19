#!/usr/bin/env bash

set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "${SCRIPT_DIR}/lib.sh"

require_command docker
docker info >/dev/null 2>&1 || die "Docker daemon is unavailable"
docker compose version >/dev/null 2>&1 || die "Docker Compose v2 is unavailable"
require_runtime_config

for key in DOMAIN POSTGRES_DB POSTGRES_USER POSTGRES_PASSWORD REDIS_PASSWORD SESSION_SECRET CRYPTO_SECRET CPA_API_KEY CPA_MANAGEMENT_KEY; do
  value="$(env_value "$key")"
  [[ -n "$value" ]] || die "$key is empty in .env"
  [[ "$value" != CHANGE_ME* ]] || die "$key still contains a placeholder"
done

domain="$(env_value DOMAIN)"
[[ "$domain" != http* && "$domain" != */* ]] || die "DOMAIN must be a bare hostname"
validate_identifier POSTGRES_DB "$(env_value POSTGRES_DB)"
validate_identifier POSTGRES_USER "$(env_value POSTGRES_USER)"

for file in \
  "${PROJECT_ROOT}/nginx/ssl/origin.pem" \
  "${PROJECT_ROOT}/nginx/ssl/origin.key" \
  "${PROJECT_ROOT}/nginx/ssl/cloudflare-origin-pull-ca.pem"; do
  require_file "$file"
done

key_mode="$(stat -c '%a' "${PROJECT_ROOT}/nginx/ssl/origin.key")"
if (( 10#$key_mode > 600 )); then
  die "nginx/ssl/origin.key is too permissive (mode ${key_mode}); run chmod 600"
fi

compose config --quiet
log "configuration checks passed"
