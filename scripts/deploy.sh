#!/usr/bin/env bash
# Fast-forward a Laravel checkout on cPanel and run the configured release steps.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

require_var DEPLOY_PATH
require_var GIT_BRANCH
require_var GIT_REMOTE
require_var PHP_BINARY
require_var COMPOSER_PATH
require_var COMPOSER_MODE
require_bool BUILD_FRONTEND
require_bool RUN_MIGRATIONS
require_bool BACKUP_DATABASE
require_bool OPTIMIZE
require_bool CACHE_ROUTES
require_bool CACHE_EVENTS
require_bool RESTART_QUEUES
require_bool MAINTENANCE_MODE

export GIT_TERMINAL_PROMPT=0
export COMPOSER_NO_INTERACTION=1

bash "${SCRIPT_DIR}/validate-environment.sh"

state="$(state_root)"
lock_dir="${state}/locks"
mkdir -p "$lock_dir"
chmod 700 "$state" "$lock_dir"
lock_file="${lock_dir}/$(hash_path "$DEPLOY_PATH").lock"
exec 9>"$lock_file"
if ! flock -n 9; then
  die "Another deployment holds the lock for ${DEPLOY_PATH}"
fi
log "Deployment lock acquired"

maintenance_started=0
release_sha=""

bring_site_up() {
  if [[ "$maintenance_started" == 1 ]]; then
    log "Bringing the application out of maintenance mode"
    "$PHP_BINARY" artisan up || warn "php artisan up failed; check maintenance mode manually"
    maintenance_started=0
  fi
}

on_exit() {
  local status="$1"
  bring_site_up
  if [[ "$status" -ne 0 ]]; then
    log "Deployment failed. No database backup was restored and .env was not modified."
  fi
}
trap 'on_exit $?' EXIT

cd "$DEPLOY_PATH"

if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
  git status --porcelain --untracked-files=no >&2
  die "Tracked production files differ from Git. Commit or discard them manually before deploying."
fi
log "Working tree has no unexpected tracked changes"

log "Fetching ${GIT_REMOTE} ${GIT_BRANCH}"
git fetch --prune "$GIT_REMOTE" "$GIT_BRANCH"

upstream="${GIT_REMOTE}/${GIT_BRANCH}"
git rev-parse --verify "${upstream}^{commit}" >/dev/null

if ! git merge-base --is-ancestor HEAD "$upstream"; then
  die "Remote ${upstream} is not a fast-forward of HEAD. Refusing to reset. See docs/ROLLBACK.md."
fi

log "Fast-forwarding to ${upstream}"
git merge --ff-only "$upstream"
release_sha="$(git rev-parse HEAD)"
log "Checked out ${release_sha}"

composer_flags=()
if [[ -n "${COMPOSER_FLAGS:-}" ]]; then
  # shellcheck disable=SC2206
  raw_flags=(${COMPOSER_FLAGS})
  for flag in "${raw_flags[@]}"; do
    case "$flag" in
      --no-dev|--prefer-dist|--no-interaction|--optimize-autoloader|--no-scripts|--classmap-authoritative|--no-progress)
        composer_flags+=("$flag")
        ;;
      *)
        die "Composer flag is not allowed: ${flag}"
        ;;
    esac
  done
fi

log "Installing Composer dependencies"
if [[ "$COMPOSER_MODE" == php ]]; then
  if [[ ${#composer_flags[@]} -eq 0 ]]; then
    "$PHP_BINARY" "$COMPOSER_PATH" install
  else
    "$PHP_BINARY" "$COMPOSER_PATH" install "${composer_flags[@]}"
  fi
else
  if [[ ${#composer_flags[@]} -eq 0 ]]; then
    "$COMPOSER_PATH" install
  else
    "$COMPOSER_PATH" install "${composer_flags[@]}"
  fi
fi

if [[ "$BUILD_FRONTEND" == true ]]; then
  [[ -f package.json ]] || die "frontend build was requested, but package.json is missing"
  preset="${FRONTEND_PRESET:-npm}"
  script_name="${NPM_SCRIPT:-build}"
  require_match NPM_SCRIPT "$script_name" '^[A-Za-z0-9:_-]+$'
  case "$preset" in
    npm)
      command -v npm >/dev/null 2>&1 || die "npm is not installed. Use frontend_mode runner or install Node on the server."
      npm ci
      npm run "$script_name"
      ;;
    yarn)
      command -v yarn >/dev/null 2>&1 || die "yarn is not installed"
      yarn install --frozen-lockfile
      yarn run "$script_name"
      ;;
    pnpm)
      command -v pnpm >/dev/null 2>&1 || die "pnpm is not installed"
      pnpm install --frozen-lockfile
      pnpm run "$script_name"
      ;;
    *)
      die "FRONTEND_PRESET must be npm, yarn, or pnpm"
      ;;
  esac
  log "Frontend assets built with ${preset}"
else
  log "Server-side frontend build is disabled"
fi

if [[ "$BACKUP_DATABASE" == true ]]; then
  bash "${SCRIPT_DIR}/backup.sh"
else
  log "Database backup is disabled"
  if [[ "$RUN_MIGRATIONS" == true ]]; then
    die "RUN_MIGRATIONS is true while BACKUP_DATABASE is false. Enable a backup or set both to false."
  fi
fi

if [[ "$MAINTENANCE_MODE" == true ]]; then
  log "Enabling maintenance mode"
  "$PHP_BINARY" artisan down --retry=60 --no-interaction
  maintenance_started=1
fi

if [[ "$RUN_MIGRATIONS" == true ]]; then
  log "Running database migrations"
  "$PHP_BINARY" artisan migrate --force --no-interaction
else
  log "Database migrations are disabled"
fi

if [[ "$OPTIMIZE" == true ]]; then
  log "Caching Laravel configuration and views"
  "$PHP_BINARY" artisan config:cache
  "$PHP_BINARY" artisan view:cache
  if [[ "$CACHE_ROUTES" == true ]]; then
    log "Caching routes because cache_routes is enabled"
    "$PHP_BINARY" artisan route:cache
  else
    log "Route caching is disabled. Enable it only for applications without closure routes."
  fi
  if [[ "$CACHE_EVENTS" == true ]]; then
    if "$PHP_BINARY" artisan list --raw 2>/dev/null | awk '{print $1}' | grep -qx 'event:cache'; then
      "$PHP_BINARY" artisan event:cache
    else
      log "event:cache is not available in this Laravel version"
    fi
  fi
else
  log "Laravel optimization is disabled"
fi

if [[ "$RESTART_QUEUES" == true ]]; then
  log "Signalling queue workers to restart"
  "$PHP_BINARY" artisan queue:restart
fi

bash "${SCRIPT_DIR}/health-check.sh"

record_dir="${state}/releases/$(hash_path "$DEPLOY_PATH")"
mkdir -p "$record_dir"
chmod 700 "$record_dir"
record_file="${record_dir}/releases.log"
printf '%s %s %s success\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$release_sha" "$GIT_BRANCH" >> "$record_file"
chmod 600 "$record_file"
log "Recorded deployed commit ${release_sha}"

bring_site_up
trap - EXIT
log "Deployment lock released"
log "Deployment finished"
