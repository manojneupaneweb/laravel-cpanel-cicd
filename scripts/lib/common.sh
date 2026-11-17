#!/usr/bin/env bash
# Shared helpers for the Laravel cPanel deployment scripts.
# Shell functions only. Do not execute this file directly.

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  printf 'common.sh must be sourced, not executed\n' >&2
  exit 1
fi

log() {
  printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"
}

die() {
  printf '[ERROR] %s\n' "$*" >&2
  exit 1
}

warn() {
  printf '[WARN] %s\n' "$*" >&2
}

require_var() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    die "Required variable ${name} is empty"
  fi
}

require_bool() {
  local name="$1"
  local value="${!name:-}"
  case "$value" in
    true|false) ;;
    *) die "${name} must be true or false" ;;
  esac
}

require_match() {
  local name="$1"
  local value="$2"
  local pattern="$3"
  if [[ ! "$value" =~ $pattern ]]; then
    die "${name} contains unsupported characters"
  fi
}

reject_traversal() {
  local name="$1"
  local value="$2"
  if [[ "$value" == *..* ]]; then
    die "${name} must not contain '..'"
  fi
}

hash_path() {
  local value="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$value" | sha256sum | awk '{print $1}'
  else
    printf '%s' "$value" | shasum -a 256 | awk '{print $1}'
  fi
}

read_env_value() {
  local key="$1"
  local file="$2"
  local line value

  [[ -f "$file" ]] || die "Environment file not found: ${file}"
  line="$(grep -E "^[[:space:]]*(export[[:space:]]+)?${key}=" "$file" | tail -n 1 || true)"
  [[ -n "$line" ]] || return 1

  value="${line#*=}"
  value="${value%$'\r'}"
  if [[ "$value" == \"*\" && "$value" == *\" ]]; then
    value="${value:1:${#value}-2}"
  elif [[ "$value" == \'*\' && "$value" == *\' ]]; then
    value="${value:1:${#value}-2}"
  else
    value="${value%%[[:space:]]#*}"
  fi

  # The patterns are quoted on purpose so the shell does not evaluate them.
  # shellcheck disable=SC2016
  if [[ "$value" == *'$('* || "$value" == *'`'* ]]; then
    die ".env value for ${key} contains command substitution; refusing to read it"
  fi
  if [[ "$value" == *$'\n'* ]]; then
    die ".env value for ${key} contains a newline"
  fi

  printf '%s' "$value"
}

state_root() {
  printf '%s\n' "${DEPLOY_STATE_DIR:-${HOME}/.laravel-cpanel-cicd}"
}
