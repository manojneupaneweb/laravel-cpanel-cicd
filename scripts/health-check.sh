#!/usr/bin/env bash
# Application sanity check run on the server after code is updated.
# Public URL checks run from GitHub Actions so shared hosting does not need
# to reach its own public hostname.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

require_var DEPLOY_PATH
require_var PHP_BINARY

[[ -f "${DEPLOY_PATH}/artisan" ]] || die "artisan is missing from ${DEPLOY_PATH}"

version="$("$PHP_BINARY" "${DEPLOY_PATH}/artisan" --version)"
log "Artisan responded: ${version}"

if [[ "${HEALTH_CHECK_FROM:-runner}" == server ]]; then
  require_var HEALTH_CHECK_URL
  require_match HEALTH_CHECK_URL "$HEALTH_CHECK_URL" '^https?://[^[:space:]\"'"'"']+$'
  command -v curl >/dev/null 2>&1 || die "curl is required for a server-side health check"
  code="$(curl -fsS --retry 3 --retry-delay 2 --max-time 20 -o /dev/null -w '%{http_code}' "$HEALTH_CHECK_URL")"
  log "Server-side health check returned HTTP ${code}"
else
  log "Public health check is delegated to the GitHub Actions runner"
fi
