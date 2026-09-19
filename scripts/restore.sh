#!/usr/bin/env bash

set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "${SCRIPT_DIR}/lib.sh"

usage() {
  cat <<'EOF'
Usage: ./scripts/restore.sh <backup.tar.gz> --confirm

Restores PostgreSQL, application secrets, New API data, CPA credentials and
TLS files. Database/cache passwords and the current domain stay unchanged. For
a new-host disaster recovery, copy the full .env from the archive first.
EOF
}

[[ $# -eq 2 && "$2" == "--confirm" ]] || {
  usage
  exit 2
}

archive="$(realpath "$1")"
require_file "$archive"
require_command docker
require_command tar
require_command sha256sum
require_runtime_config

if [[ -f "${archive}.sha256" ]]; then
  (cd "$(dirname "$archive")" && sha256sum --check "$(basename "${archive}.sha256")")
fi

while IFS= read -r entry; do
  case "$entry" in
    /* | *../*) die "backup contains an unsafe path: $entry" ;;
  esac
done < <(tar -tzf "$archive")

temporary="$(mktemp -d)"
trap 'rm -rf "$temporary"' EXIT
tar -C "$temporary" -xzf "$archive"
payload="${temporary}/payload"
require_file "${payload}/database/newapi.dump"
require_file "${payload}/cpa/config.yaml"
require_file "${payload}/.env"

postgres_user="$(env_value POSTGRES_USER)"
postgres_db="$(env_value POSTGRES_DB)"
validate_identifier POSTGRES_USER "$postgres_user"
validate_identifier POSTGRES_DB "$postgres_db"

log "creating a safety backup before restore"
"${SCRIPT_DIR}/backup.sh"

log "stopping request-serving containers"
compose stop nginx new-api cpa
compose up -d postgres redis

set_env_value() {
  local key="$1"
  local value="$2"
  local temporary_env
  temporary_env="$(mktemp "${PROJECT_ROOT}/.env.restore.XXXXXX")"
  awk -F= -v key="$key" -v value="$value" '
    $1 == key { print key "=" value; next }
    { print }
  ' "$ENV_FILE" >"$temporary_env"
  mv "$temporary_env" "$ENV_FILE"
  chmod 600 "$ENV_FILE"
}

# These values are coupled to the restored database and CPA configuration.
# Keep infrastructure passwords/domain from the current host so an initialized
# PostgreSQL volume does not become inaccessible after the restore.
for key in SESSION_SECRET CRYPTO_SECRET CPA_API_KEY CPA_MANAGEMENT_KEY; do
  restored_value="$(env_value "$key" "${payload}/.env")"
  [[ -n "$restored_value" ]] || die "backup .env is missing $key"
  set_env_value "$key" "$restored_value"
done

restore_stamp="$(date -u +%Y%m%dT%H%M%SZ)"
if [[ -d "${PROJECT_ROOT}/cpa/auths" ]]; then
  mv "${PROJECT_ROOT}/cpa/auths" "${PROJECT_ROOT}/cpa/auths.pre-restore-${restore_stamp}"
fi
mkdir -p "${PROJECT_ROOT}/cpa/auths"
cp -a "${payload}/cpa/auths/." "${PROJECT_ROOT}/cpa/auths/"
cp "${payload}/cpa/config.yaml" "${PROJECT_ROOT}/cpa/config.yaml"
chmod 600 "${PROJECT_ROOT}/cpa/config.yaml"

if [[ -d "${payload}/new-api/data" ]]; then
  if [[ -d "${PROJECT_ROOT}/data/new-api" ]]; then
    mv "${PROJECT_ROOT}/data/new-api" "${PROJECT_ROOT}/data/new-api.pre-restore-${restore_stamp}"
  fi
  mkdir -p "${PROJECT_ROOT}/data/new-api"
  cp -a "${payload}/new-api/data/." "${PROJECT_ROOT}/data/new-api/"
fi

if [[ -d "${payload}/nginx/ssl" ]]; then
  if [[ -d "${PROJECT_ROOT}/nginx/ssl" ]]; then
    mv "${PROJECT_ROOT}/nginx/ssl" "${PROJECT_ROOT}/nginx/ssl.pre-restore-${restore_stamp}"
  fi
  mkdir -p "${PROJECT_ROOT}/nginx/ssl"
  cp -a "${payload}/nginx/ssl/." "${PROJECT_ROOT}/nginx/ssl/"
  chmod 600 "${PROJECT_ROOT}/nginx/ssl/origin.key"
fi

log "restoring PostgreSQL"
compose exec -T postgres psql \
  --username "$postgres_user" \
  --dbname postgres \
  --set ON_ERROR_STOP=1 \
  --command "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '${postgres_db}' AND pid <> pg_backend_pid();"
compose exec -T postgres pg_restore \
  --username "$postgres_user" \
  --dbname postgres \
  --clean \
  --if-exists \
  --create \
  --no-owner <"${payload}/database/newapi.dump"

compose up -d
"${SCRIPT_DIR}/healthcheck.sh" --wait
log "restore completed; pre-restore CPA and TLS directories were retained with suffix ${restore_stamp}"
