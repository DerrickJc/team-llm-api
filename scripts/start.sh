#!/usr/bin/env bash

set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "${SCRIPT_DIR}/lib.sh"

"${SCRIPT_DIR}/doctor.sh"
compose pull
compose up -d --remove-orphans
"${SCRIPT_DIR}/healthcheck.sh" --wait
