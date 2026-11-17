#!/usr/bin/env bash
# Move the checkout back to an ancestor commit.
# This does not restore a database backup.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

require_var DEPLOY_PATH
require_var TARGET_SHA
require_var CONFIRM

if [[ "$CONFIRM" != rollback ]]; then
  die "Refusing rollback. Re-run with CONFIRM=rollback after reading docs/ROLLBACK.md"
fi

require_match TARGET_SHA "$TARGET_SHA" '^[0-9a-fA-F]{7,40}$'
reject_traversal DEPLOY_PATH "$DEPLOY_PATH"
require_match DEPLOY_PATH "$DEPLOY_PATH" '^/[-A-Za-z0-9._@/+]+$'

[[ -d "${DEPLOY_PATH}/.git" ]] || die "Deployment directory is not a Git checkout"

state="$(state_root)"
lock_dir="${state}/locks"
mkdir -p "$lock_dir"
chmod 700 "$state" "$lock_dir"
lock_file="${lock_dir}/$(hash_path "$DEPLOY_PATH").lock"
exec 9>"$lock_file"
if ! flock -n 9; then
  die "A deployment or rollback already holds the lock"
fi

cd "$DEPLOY_PATH"

if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
  git status --porcelain --untracked-files=no >&2
  die "Tracked files have local changes. Rollback was not started."
fi

git rev-parse --verify "${TARGET_SHA}^{commit}" >/dev/null
if ! git merge-base --is-ancestor "$TARGET_SHA" HEAD; then
  die "TARGET_SHA must be an ancestor of HEAD. This script will not rewrite diverged history."
fi

current="$(git rev-parse HEAD)"
resolved="$(git rev-parse "${TARGET_SHA}^{commit}")"
if [[ "$current" == "$resolved" ]]; then
  die "HEAD is already ${resolved}"
fi

log "Moving HEAD from ${current} to ${resolved} with git reset --keep"
log "Database backups are not restored by this command"
git reset --keep "$resolved"

log "Rollback finished at $(git rev-parse --short HEAD)"
log "Run Composer install and the relevant Laravel cache commands for this commit before serving traffic"
log "A previous database backup, if one was taken, remains untouched under the deploy state directory"
