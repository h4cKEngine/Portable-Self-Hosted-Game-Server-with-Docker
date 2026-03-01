#!/bin/bash

set -Eeuo pipefail

# --- Autoload env/.env if run manually (outside run-server.sh)
if [ -z "${_DMS_ENV_LOADED:-}" ]; then
  ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
  if [ -f "$ROOT_DIR/env/.env" ]; then
    set -a; . "$ROOT_DIR/env/.env"; set +a
    export _DMS_ENV_LOADED=1
  fi
fi

# ==============================================================================
# CONFIGURATION
# ==============================================================================
: "${MUTEX_FILE:=mutex.txt}"
: "${RCLONE_CONF_HOST:=./env/rclone.conf}"
: "${RETRIES:=5}"
: "${SLEEP_SECS:=0.5}"
: "${CLOUD_MUTEX_DIR:=/Root/modpack}"

# ==============================================================================
# UTILITIES
# ==============================================================================
log() { printf '[INFO] %s\n' "$*"; }
err() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

# Ensures dependencies are present
ensure_dependencies() {
  command -v rclone >/dev/null 2>&1 || err "rclone not found"
  [[ -f "$RCLONE_CONF_HOST" ]] || err "rclone.conf not found: $RCLONE_CONF_HOST"
}

# Wrapper for rclone
rc() {
  rclone --config "$RCLONE_CONF_HOST" "$@"
}

# ==============================================================================
# PATH LOGIC
# ==============================================================================
# Derives the remote directory from environment variables
derive_remote_dir() {
  # If explicitly set, use that
  if [ -n "${MUTEX_REMOTE_DIR:-}" ]; then 
    printf '%s' "${MUTEX_REMOTE_DIR%/}"
    return
  fi
  
  # Otherwise derive from RESTIC_REPOSITORY (e.g. rclone:mega:/backup -> mega:/backup)
  [ -n "${RESTIC_REPOSITORY:-}" ] || err "MUTEX_REMOTE_DIR missing. Set it or define RESTIC_REPOSITORY."
  
  local repo="${RESTIC_REPOSITORY#rclone:}"    # remove rclone: prefix
  local remote="${repo%%:*}"                   # extract remote name (e.g. mega)
  local sub="${CLOUD_MUTEX_DIR#/Root}"         # path cleanup
  sub="${sub#/}"
  
  printf '%s' "${remote}:/${sub}"
}

# Initializes path variables
init_paths() {
  REMOTE_DIR="$(derive_remote_dir)"
  REMOTE_FILE="${REMOTE_DIR}/${MUTEX_FILE}"
}

# ==============================================================================
# CORE OPERATIONS
# ==============================================================================

# Ensure remote directory and mutex file exist (default 0)
ensure_initialized() {
  rc mkdir "$REMOTE_DIR" >/dev/null 2>&1 || true
  
  # If file does not exist, create it with '0'
  if ! rc ls "$REMOTE_FILE" >/dev/null 2>&1; then
    local tmp; tmp="$(mktemp)"; printf '0\n' > "$tmp"
    rc copyto --ignore-times "$tmp" "$REMOTE_FILE" >/dev/null
    rm -f "$tmp"
  fi
}

# Reads current state (0 or 1)
read_flag() {
  local out val
  # If reading fails (e.g. network), assume 0 for safety or handle error?
  if ! out="$(rc cat "$REMOTE_FILE" 2>/dev/null || true)"; then 
    echo 0; return
  fi
  
  # Read only the first useful byte (0 or 1)
  val="$(printf '%s' "$out" | dd bs=1 count=1 2>/dev/null | tr -dc '01' || true)"
  
  if [ "$val" = "1" ]; then echo 1; else echo 0; fi
}

# Robust write: Delete + Upload (to avoid overwrite issues on some clouds)
write_flag() {
  local val="$1"
  [[ "$val" =~ ^(0|1)$ ]] || err "Invalid value: use 0 or 1"
  
  local tmp; tmp="$(mktemp)"
  printf '%s\n' "$val" > "$tmp"
  
  # 1. Delete old (ignore errors if not exists)
  rc deletefile "$REMOTE_FILE" >/dev/null 2>&1 || true
  
  # 2. Upload new
  rc copyto --ignore-times "$tmp" "$REMOTE_FILE" >/dev/null
  rm -f "$tmp"
  
  # 3. Paranoia check
  local check
  check="$(rc cat "$REMOTE_FILE" 2>/dev/null | dd bs=1 count=1 2>/dev/null | tr -dc '01' || true)"
  [ "$check" = "$val" ] || err "Write verification failed: wrote $val, read $check"
}

# Compare-And-Swap: Set 'new_val' ONLY IF current value is 'expected_val'
cas_update() {
  local expected="$1"
  local new_val="$2"
  local max_retries="${3:-$RETRIES}"
  local sleep_time="${4:-$SLEEP_SECS}"
  
  local i current
  for i in $(seq 1 "$max_retries"); do
    current="$(read_flag)"
    
    if [ "$current" = "$expected" ]; then
      write_flag "$new_val"
      echo "$new_val"
      return 0
    fi
    
    sleep "$sleep_time"
  done
  
  err "CAS failed after $max_retries attempts. (Current state: $current, Expected: $expected)"
}

# ==============================================================================
# COMMANDS
# ==============================================================================
cmd_get() {
  ensure_initialized
  read_flag
}

cmd_set() {
  local val="${1:-}"
  [ -z "$val" ] && err "Specify value: set 0|1"
  ensure_initialized
  write_flag "$val"
  echo "$val"
}

cmd_cas() {
  local expect="${1:-}" 
  local newv="${2:-}"
  [ -z "$expect" ] || [ -z "$newv" ] && err "Usage: cas <expected> <new>"
  
  ensure_initialized
  cas_update "$expect" "$newv"
}

cmd_ensure() {
  ensure_initialized
}

cmd_diag() {
  echo "--- Rclone Mutex Diagnostics ---"
  echo "CONF: $RCLONE_CONF_HOST"
  echo "REMOTE_DIR: $REMOTE_DIR"
  echo "REMOTE_FILE: $REMOTE_FILE"
  echo "--- CHECK LS ---"
  rc ls "$REMOTE_DIR" || echo "ls error"
  echo "--- CHECK CAT ---"
  rc cat "$REMOTE_FILE" 2>/dev/null | hd || echo "(empty content or error)"
}

usage() {
  cat <<EOF
Usage: $(basename "$0") [command] [arguments...]

Commands:
  get             Reads mutex state (0 or 1)
  set 0|1         Forces mutex state
  cas <exp> <new> Compare-And-Swap (changes to <new> only if it is <exp>)
  ensure          Ensures mutex file exists
  diag            Prints debug info
EOF
}

# ==============================================================================
# MAIN
# ==============================================================================
# Main entry point for Rclone Mutex
main() {
  ensure_dependencies
  init_paths
  
  local cmd="${1:-}"
  shift || true
  
  case "$cmd" in
    get|status) cmd_get "$@" ;;
    set)        cmd_set "$@" ;;
    cas)        cmd_cas "$@" ;;
    ensure)     cmd_ensure "$@" ;;
    diag)       cmd_diag "$@" ;;
    *)          usage; exit 1 ;;
  esac
}

main "$@"
