#!/usr/bin/env bash

set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "${SCRIPT_DIR}/lib.sh"

require_command docker
require_command tar
require_command sha256sum
require_runtime_config

postgres_user="$(env_value POSTGRES_USER)"
postgres_db="$(env_value POSTGRES_DB)"
validate_identifier POSTGRES_USER "$postgres_user"
validate_identifier POSTGRES_DB "$postgres_db"

backup_dir="$(env_value BACKUP_DIR)"
retention_days="$(env_value BACKUP_RETENTION_DAYS)"
backup_dir="${backup_dir:-./backups}"
retention_days="${retention_days:-7}"
[[ "$retention_days" =~ ^[0-9]+$ ]] || die "BACKUP_RETENTION_DAYS must be an integer"

if [[ "$backup_dir" != /* ]]; then
  backup_dir="${PROJECT_ROOT}/${backup_dir#./}"
fi
mkdir -p "$backup_dir"

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
archive="${backup_dir}/team-llm-api-${timestamp}.tar.gz"
temporary="$(mktemp -d "${backup_dir}/.backup.XXXXXX")"
trap 'rm -rf "$temporary"' EXIT
payload="${temporary}/payload"
mkdir -p "$payload/database" "$payload/cpa" "$payload/nginx" "$payload/new-api"

postgres_container="$(compose ps -q postgres)"
[[ -n "$postgres_container" ]] || die "postgres is not running"

log "dumping PostgreSQL"
compose exec -T postgres pg_dump \
  --username "$postgres_user" \
  --dbname "$postgres_db" \
  --format=custom \
  --create \
  --no-owner >"${payload}/database/newapi.dump"

cp "$ENV_FILE" "${payload}/.env"
cp "${PROJECT_ROOT}/cpa/config.yaml" "${payload}/cpa/config.yaml"
cp -a "${PROJECT_ROOT}/cpa/auths" "${payload}/cpa/auths"
cp -a "${PROJECT_ROOT}/nginx/ssl" "${payload}/nginx/ssl"
cp -a "${PROJECT_ROOT}/data/new-api" "${payload}/new-api/data"

{
  printf 'created_at=%s\n' "$timestamp"
  printf 'project=team-llm-api\n'
  printf 'new_api_version=%s\n' "$(env_value NEW_API_VERSION)"
  printf 'cpa_version=%s\n' "$(env_value CPA_VERSION)"
  printf 'postgres_version=%s\n' "$(env_value POSTGRES_VERSION)"
  printf 'redis_version=%s\n' "$(env_value REDIS_VERSION)"
  printf 'nginx_version=%s\n' "$(env_value NGINX_VERSION)"
} >"${payload}/manifest.env"

tar -C "$temporary" -czf "$archive" payload
sha256sum "$archive" >"${archive}.sha256"
chmod 600 "$archive" "${archive}.sha256"

find "$backup_dir" -maxdepth 1 -type f \
  \( -name 'team-llm-api-*.tar.gz' -o -name 'team-llm-api-*.tar.gz.sha256' \) \
  -mtime "+${retention_days}" -delete

log "backup written to ${archive}"
log "the archive contains credentials and must be stored as a secret"
