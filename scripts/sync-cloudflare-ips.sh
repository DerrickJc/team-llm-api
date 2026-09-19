#!/usr/bin/env bash

set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "${SCRIPT_DIR}/lib.sh"

require_command curl
target="${PROJECT_ROOT}/nginx/conf.d/cloudflare-realip.conf"
temporary="$(mktemp "${PROJECT_ROOT}/nginx/conf.d/cloudflare-realip.XXXXXX")"
trap 'rm -f "$temporary"' EXIT

{
  printf '# Generated from https://www.cloudflare.com/ips/ on %s\n' "$(date -u +%F)"
  curl --fail --silent --show-error https://www.cloudflare.com/ips-v4 | sed '/^$/d; s/^/set_real_ip_from /; s/$/;/'
  curl --fail --silent --show-error https://www.cloudflare.com/ips-v6 | sed '/^$/d; s/^/set_real_ip_from /; s/$/;/'
} >"$temporary"

count="$(grep -c '^set_real_ip_from ' "$temporary")"
(( count >= 20 )) || die "downloaded Cloudflare IP list looks incomplete (${count} entries)"
mv "$temporary" "$target"
trap - EXIT

if [[ -f "$ENV_FILE" ]] && compose ps -q nginx >/dev/null 2>&1 && [[ -n "$(compose ps -q nginx)" ]]; then
  compose exec -T nginx nginx -t
  compose exec -T nginx nginx -s reload
fi

log "Cloudflare real-IP list updated (${count} networks)"
