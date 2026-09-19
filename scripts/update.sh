#!/usr/bin/env bash

set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "${SCRIPT_DIR}/lib.sh"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/update.sh [--new-api VERSION] [--cpa VERSION]

Example:
  ./scripts/update.sh --new-api v1.0.0-rc.39 --cpa v7.3.8

The script backs up first, changes only the requested image tags, pulls them,
and checks health. On failure it restores the old tags and recreates services.
Database migrations may require a full restore from the generated backup.
EOF
}

new_api_version=""
cpa_version=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --new-api)
      [[ $# -ge 2 ]] || die "--new-api requires a value"
      new_api_version="$2"
      shift 2
      ;;
    --cpa)
      [[ $# -ge 2 ]] || die "--cpa requires a value"
      cpa_version="$2"
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

[[ -n "$new_api_version" || -n "$cpa_version" ]] || {
  usage
  exit 2
}

[[ -z "$new_api_version" ]] || validate_version NEW_API_VERSION "$new_api_version"
[[ -z "$cpa_version" ]] || validate_version CPA_VERSION "$cpa_version"
require_runtime_config

rollback_env="$(mktemp "${PROJECT_ROOT}/.env.rollback.XXXXXX")"
cp "$ENV_FILE" "$rollback_env"
chmod 600 "$rollback_env"
cleanup() {
  rm -f "$rollback_env"
}
trap cleanup EXIT

set_env_value() {
  local key="$1"
  local value="$2"
  local temporary
  temporary="$(mktemp "${PROJECT_ROOT}/.env.update.XXXXXX")"
  awk -F= -v key="$key" -v value="$value" '
    $1 == key { print key "=" value; next }
    { print }
  ' "$ENV_FILE" >"$temporary"
  mv "$temporary" "$ENV_FILE"
  chmod 600 "$ENV_FILE"
}

"${SCRIPT_DIR}/backup.sh"
[[ -z "$new_api_version" ]] || set_env_value NEW_API_VERSION "$new_api_version"
[[ -z "$cpa_version" ]] || set_env_value CPA_VERSION "$cpa_version"

services=()
[[ -z "$new_api_version" ]] || services+=(new-api)
[[ -z "$cpa_version" ]] || services+=(cpa)

if compose pull "${services[@]}" && compose up -d --remove-orphans && "${SCRIPT_DIR}/healthcheck.sh" --wait; then
  log "update completed"
  exit 0
fi

log "update failed; restoring previous image tags"
cp "$rollback_env" "$ENV_FILE"
chmod 600 "$ENV_FILE"
compose up -d --remove-orphans || true
die "image rollback attempted; restore the pre-update backup if a database migration prevents recovery"
