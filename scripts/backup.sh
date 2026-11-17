#!/usr/bin/env bash
# Create a private database backup. This script never restores data.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

require_var DEPLOY_PATH
require_bool BACKUP_DATABASE

if [[ "$BACKUP_DATABASE" != true ]]; then
  log "Database backup is disabled"
  exit 0
fi

env_file="${DEPLOY_PATH}/.env"
connection="$(read_env_value DB_CONNECTION "$env_file" || true)"
[[ -n "$connection" ]] || die "DB_CONNECTION is missing from .env"

state="$(state_root)"
backup_dir="${state}/backups/$(hash_path "$DEPLOY_PATH")"
mkdir -p "$backup_dir"
chmod 700 "$state" "${state}/backups" "$backup_dir" 2>/dev/null || chmod 700 "$backup_dir"

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
cleanup_file=""
cleanup() {
  if [[ -n "$cleanup_file" ]]; then
    rm -f "$cleanup_file"
  fi
}
trap cleanup EXIT

case "$connection" in
  sqlite)
    database="$(read_env_value DB_DATABASE "$env_file" || true)"
    [[ -n "$database" ]] || die "DB_DATABASE is missing for sqlite"
    [[ "$database" != ":memory:" ]] || die "Cannot back up an in-memory sqlite database"
    if [[ "$database" != /* ]]; then
      database="${DEPLOY_PATH}/${database}"
    fi
    [[ -f "$database" ]] || die "SQLite database file does not exist"
    target="${backup_dir}/${stamp}.sqlite.gz"
    gzip -c "$database" > "$target"
    ;;
  mysql|mariadb)
    command -v mysqldump >/dev/null 2>&1 || die "mysqldump is not installed"
    database="$(read_env_value DB_DATABASE "$env_file" || true)"
    username="$(read_env_value DB_USERNAME "$env_file" || true)"
    if ! password="$(read_env_value DB_PASSWORD "$env_file")"; then
      die "DB_PASSWORD is missing from .env"
    fi
    host="$(read_env_value DB_HOST "$env_file" || true)"
    port="$(read_env_value DB_PORT "$env_file" || true)"
    socket="$(read_env_value DB_SOCKET "$env_file" || true)"

    [[ -n "$database" && -n "$username" ]] || die "MySQL backup requires DB_DATABASE and DB_USERNAME"
    if [[ "$password" == *'"'* || "$password" == *\\* ]]; then
      die "DB_PASSWORD contains a quote or backslash. Take the backup with a host-managed tool, or use a password without those characters."
    fi
    host="${host:-127.0.0.1}"
    port="${port:-3306}"
    require_match DB_PORT "$port" '^[0-9]+$'

    defaults="${backup_dir}/.${stamp}.cnf"
    cleanup_file="$defaults"
    umask 077
    {
      printf '%s\n' '[client]'
      printf 'user=%s\n' "$username"
      printf 'password="%s"\n' "$password"
      if [[ -n "$socket" ]]; then
        printf 'socket=%s\n' "$socket"
      else
        printf 'host=%s\n' "$host"
        printf 'port=%s\n' "$port"
      fi
    } > "$defaults"
    chmod 600 "$defaults"

    target="${backup_dir}/${stamp}.sql.gz"
    mysqldump \
      --defaults-extra-file="$defaults" \
      --single-transaction \
      --quick \
      --no-tablespaces \
      "$database" | gzip -c > "$target"
    ;;
  *)
    die "BACKUP_DATABASE is true, but DB_CONNECTION '${connection}' is not supported. Supported values: mysql, mariadb, sqlite."
    ;;
esac

chmod 600 "$target"
size="$(wc -c < "$target" | tr -d ' ')"
if [[ "$size" -lt 20 ]]; then
  die "Backup file is unexpectedly small (${size} bytes)"
fi

log "Database backup written (${connection}, ${size} bytes). The path is recorded locally and is not a public web path."
printf '%s\n' "$target" > "${backup_dir}/LATEST"
chmod 600 "${backup_dir}/LATEST"
log "Latest backup pointer updated under the deploy state directory"
