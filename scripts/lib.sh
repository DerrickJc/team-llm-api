#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${PROJECT_ROOT}/.env"

log() {
  printf '[team-llm-gateway] %s\n' "$*"
}

die() {
  printf '[team-llm-gateway] ERROR: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

require_file() {
  [[ -s "$1" ]] || die "required file is missing or empty: $1"
}

env_value() {
  local key="$1"
  local file="${2:-$ENV_FILE}"
  sed -n "s/^${key}=//p" "$file" | tail -n 1
}

require_runtime_config() {
  require_file "$ENV_FILE"
  require_file "${PROJECT_ROOT}/cpa/config.yaml"
}

compose() {
  docker compose --project-directory "$PROJECT_ROOT" --env-file "$ENV_FILE" "$@"
}

validate_identifier() {
  [[ "$2" =~ ^[a-zA-Z0-9_]+$ ]] || die "$1 must contain only letters, numbers, and underscores"
}

validate_version() {
  [[ "$2" =~ ^[a-zA-Z0-9._-]+$ ]] || die "$1 contains unsupported characters"
}
