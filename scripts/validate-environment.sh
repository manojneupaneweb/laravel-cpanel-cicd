#!/usr/bin/env bash
# Verify the cPanel account can host a safe Laravel deployment.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

require_var DEPLOY_PATH
require_var PHP_BINARY
require_var PHP_VERSION
require_var COMPOSER_PATH
require_var COMPOSER_MODE
require_var GIT_BRANCH
require_var GIT_REMOTE

reject_traversal DEPLOY_PATH "$DEPLOY_PATH"
reject_traversal PHP_BINARY "$PHP_BINARY"
reject_traversal COMPOSER_PATH "$COMPOSER_PATH"
reject_traversal GIT_BRANCH "$GIT_BRANCH"
reject_traversal GIT_REMOTE "$GIT_REMOTE"

require_match DEPLOY_PATH "$DEPLOY_PATH" '^/[-A-Za-z0-9._@/+]+$'
require_match PHP_BINARY "$PHP_BINARY" '^/[-A-Za-z0-9._/+]+$'
require_match PHP_VERSION "$PHP_VERSION" '^[0-9]+\.[0-9]+$'
require_match GIT_BRANCH "$GIT_BRANCH" '^[A-Za-z0-9._/-]+$'
require_match GIT_REMOTE "$GIT_REMOTE" '^[A-Za-z0-9._/-]+$'

case "$COMPOSER_MODE" in
  php|direct) ;;
  *) die "COMPOSER_MODE must be php or direct" ;;
esac

if [[ "$COMPOSER_MODE" == php ]]; then
  require_match COMPOSER_PATH "$COMPOSER_PATH" '^/[-A-Za-z0-9._/+]+$'
else
  require_match COMPOSER_PATH "$COMPOSER_PATH" '^[A-Za-z0-9._/@+-]+$'
fi

[[ "$DEPLOY_PATH" != / ]] || die "DEPLOY_PATH must be the application directory, not /"

[[ -d "$DEPLOY_PATH" ]] || die "Deployment directory does not exist: ${DEPLOY_PATH}"
[[ -f "${DEPLOY_PATH}/artisan" ]] || die "artisan was not found in ${DEPLOY_PATH}"
[[ -f "${DEPLOY_PATH}/composer.json" ]] || die "composer.json was not found in ${DEPLOY_PATH}"
[[ -d "${DEPLOY_PATH}/.git" ]] || die "Deployment directory is not a Git checkout"

if [[ -z "$PHP_BINARY" || ! -x "$PHP_BINARY" ]]; then
  die "PHP binary is not executable: ${PHP_BINARY}"
fi

actual_php="$("$PHP_BINARY" -r 'echo PHP_MAJOR_VERSION, ".", PHP_MINOR_VERSION;')"
if [[ "$actual_php" != "$PHP_VERSION" ]]; then
  die "PHP ${PHP_BINARY} is ${actual_php}; expected ${PHP_VERSION}"
fi
log "PHP ${actual_php} matches the requested version"

if [[ "$COMPOSER_MODE" == php ]]; then
  [[ -f "$COMPOSER_PATH" ]] || die "Composer path does not exist: ${COMPOSER_PATH}"
  "$PHP_BINARY" "$COMPOSER_PATH" --version >/dev/null
else
  command -v "$COMPOSER_PATH" >/dev/null 2>&1 || die "Composer command not found: ${COMPOSER_PATH}"
  "$COMPOSER_PATH" --version >/dev/null
fi
log "Composer is reachable"

perm="$(stat -c '%a' "$DEPLOY_PATH" 2>/dev/null || stat -f '%OLp' "$DEPLOY_PATH")"
if [[ "$perm" == *7 ]]; then
  die "Deployment directory is world-writable (${perm}). Fix ownership instead of using chmod 777."
fi

env_file="${DEPLOY_PATH}/.env"
[[ -f "$env_file" ]] || die ".env is missing. Create it on the server. This template never writes .env."

env_perm="$(stat -c '%a' "$env_file" 2>/dev/null || stat -f '%OLp' "$env_file")"
if [[ "$env_perm" == *4 || "$env_perm" == *5 || "$env_perm" == *6 || "$env_perm" == *7 ]]; then
  die ".env is readable by other users (${env_perm}). Expected mode 600 or 640."
fi

if git -C "$DEPLOY_PATH" ls-files --error-unmatch .env >/dev/null 2>&1; then
  die ".env is tracked by Git. Remove it from the repository index before deploying."
fi

branch="$(git -C "$DEPLOY_PATH" rev-parse --abbrev-ref HEAD)"
if [[ "$branch" != "$GIT_BRANCH" ]]; then
  die "Checkout is on '${branch}', not '${GIT_BRANCH}'. Refusing to switch branches automatically."
fi

if ! git -C "$DEPLOY_PATH" remote get-url "$GIT_REMOTE" >/dev/null 2>&1; then
  die "Git remote '${GIT_REMOTE}' is not configured in ${DEPLOY_PATH}"
fi

available_kb="$(df -Pk "$DEPLOY_PATH" | awk 'NR==2 {print $4}')"
if [[ -n "$available_kb" && "$available_kb" -lt 204800 ]]; then
  die "Less than 200 MB free on the deployment filesystem"
fi

for dir in storage bootstrap/cache; do
  if [[ -d "${DEPLOY_PATH}/${dir}" && ! -w "${DEPLOY_PATH}/${dir}" ]]; then
    die "${dir} is not writable by the deploy user. Fix ownership; do not chmod 777."
  fi
done

log "Environment validation passed"
