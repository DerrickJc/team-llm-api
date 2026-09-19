#!/usr/bin/env bash

set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "${SCRIPT_DIR}/lib.sh"

for script in "${PROJECT_ROOT}"/scripts/*.sh; do
  bash -n "$script"
done

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck "${PROJECT_ROOT}"/scripts/*.sh
fi

if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  docker compose \
    --project-directory "$PROJECT_ROOT" \
    --env-file "${PROJECT_ROOT}/.env.example" \
    config --quiet
fi

log "static validation passed"
