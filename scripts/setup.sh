#!/usr/bin/env bash

set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "${SCRIPT_DIR}/lib.sh"

usage() {
  cat <<'EOF'
Usage: ./scripts/setup.sh <api.example.com>

Creates .env, generates random secrets, renders cpa/config.yaml, downloads the
public Cloudflare AOP CA certificate, and prepares runtime directories.
It does not create the Cloudflare Origin CA certificate and private key.
EOF
}

[[ $# -eq 1 ]] || {
  usage
  exit 2
}

domain="$1"
[[ "$domain" =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$ ]] || \
  die "expected a hostname such as api.example.com"

require_command openssl
require_command curl

if [[ -e "$ENV_FILE" || -e "${PROJECT_ROOT}/cpa/config.yaml" ]]; then
  die ".env or cpa/config.yaml already exists; setup will not overwrite secrets"
fi

umask 077
cp "${PROJECT_ROOT}/.env.example" "$ENV_FILE"

set_env_value() {
  local key="$1"
  local value="$2"
  local temporary
  temporary="$(mktemp "${PROJECT_ROOT}/.env.XXXXXX")"
  awk -F= -v key="$key" -v value="$value" '
    $1 == key { print key "=" value; next }
    { print }
  ' "$ENV_FILE" >"$temporary"
  mv "$temporary" "$ENV_FILE"
}

set_env_value DOMAIN "$domain"
set_env_value POSTGRES_PASSWORD "$(openssl rand -hex 24)"
set_env_value REDIS_PASSWORD "$(openssl rand -hex 24)"
set_env_value SESSION_SECRET "$(openssl rand -hex 32)"
set_env_value CRYPTO_SECRET "$(openssl rand -hex 32)"
set_env_value CPA_API_KEY "sk-cpa-$(openssl rand -hex 24)"
set_env_value CPA_MANAGEMENT_KEY "$(openssl rand -hex 24)"

cpa_api_key="$(env_value CPA_API_KEY)"
cpa_management_key="$(env_value CPA_MANAGEMENT_KEY)"
sed \
  -e "s/__CPA_API_KEY__/${cpa_api_key}/g" \
  -e "s/__CPA_MANAGEMENT_KEY__/${cpa_management_key}/g" \
  "${PROJECT_ROOT}/cpa/config.example.yaml" >"${PROJECT_ROOT}/cpa/config.yaml"

mkdir -p \
  "${PROJECT_ROOT}/backups" \
  "${PROJECT_ROOT}/cpa/auths" \
  "${PROJECT_ROOT}/cpa/logs" \
  "${PROJECT_ROOT}/cpa/plugins" \
  "${PROJECT_ROOT}/data/new-api" \
  "${PROJECT_ROOT}/logs/new-api" \
  "${PROJECT_ROOT}/nginx/ssl"

curl --fail --silent --show-error --location \
  https://developers.cloudflare.com/ssl/static/authenticated_origin_pull_ca.pem \
  --output "${PROJECT_ROOT}/nginx/ssl/cloudflare-origin-pull-ca.pem"

chmod 600 "$ENV_FILE" "${PROJECT_ROOT}/cpa/config.yaml"
chmod 644 "${PROJECT_ROOT}/nginx/ssl/cloudflare-origin-pull-ca.pem"

log "configuration created for ${domain}"
log "next: install nginx/ssl/origin.pem and nginx/ssl/origin.key, then run ./scripts/start.sh"
