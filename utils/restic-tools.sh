#!/bin/bash

set -euo pipefail

# =========================
# Functions:
#   - exec_restic <args...>
#   - unlock_repo
#   - restore_world_offline [SNAPSHOT_ID|latest]
#   - backup_world_offline
#
# CLI:
#   ./restic-tools.sh exec <args...>
#   ./restic-tools.sh unlock
#   ./restic-tools.sh restore [SNAPSHOT_ID|latest]
#   ./restic-tools.sh backup
# =========================

# --- Find project root and ENV ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [[ -f "$SCRIPT_DIR/env/.env" ]]; then
  PROJECT_ROOT="$SCRIPT_DIR"
  ENV_FILE="$SCRIPT_DIR/env/.env"
elif [[ -f "$SCRIPT_DIR/../env/.env" ]]; then
  PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
  ENV_FILE="$PROJECT_ROOT/env/.env"
else
  echo "[ERROR] env/.env not found in $SCRIPT_DIR or parent"
  exit 1
fi
cd "$PROJECT_ROOT"

# --- Load ENV ---
set -a
source "$ENV_FILE"
set +a

# --- Variables & default (override via .env) ---
RESTIC_HOSTNAME="${RESTIC_HOSTNAME:-Mondo}"
RESTIC_PASSWORD="${RESTIC_PASSWORD:-}"
RESTIC_REPOSITORY="${RESTIC_REPOSITORY:-}"
RESTIC_IMAGE="${RESTIC_IMAGE:-docker.io/tofran/restic-rclone:0.17.0_1.68.2}"

# Default UID/GID
: "${TARGET_UID:=$(id -u)}"
: "${TARGET_GID:=$(id -g)}"

# rclone.conf path (host -> container)
RCLONE_CONF_HOST="${RCLONE_CONF_HOST:-./env/rclone.conf}"
# correct fallback in container
RCLONE_CONF_CONT="${RCLONE_CONFIG:-/root/.config/rclone/rclone.conf}"

# World folder on host (if exists, always bind-mount it)
WORLD_HOST_DIR="${WORLD_HOST_DIR:-$PROJECT_ROOT/world}"

# MC data volume name and MC container name (for offline check)
MC_CONTAINER_NAME="${MC_CONTAINER_NAME:-modpack}"

# CSV Tags for backups
RESTIC_TAG="${RESTIC_TAG:-mc_backups}"

# (optional) Docker network for run (to force it)
DOCKER_NETWORK="${DOCKER_NETWORK:-}"

# --- Preliminary checks ---
[[ -n "$RESTIC_PASSWORD" ]]   || { echo "[ERROR] RESTIC_PASSWORD missing/empty in $ENV_FILE"; exit 1; }
[[ -n "$RESTIC_REPOSITORY" ]] || { echo "[ERROR] RESTIC_REPOSITORY missing/empty in $ENV_FILE"; exit 1; }
[[ -f "$RCLONE_CONF_HOST"  ]] || { echo "[ERROR] rclone.conf not found: $RCLONE_CONF_HOST"; exit 1; }

# --- Common helpers ---
# Runs restic inside a docker container
docker_restic() {
  # Build optional --network argument
  local net_args=()
  [[ -n "$DOCKER_NETWORK" ]] && net_args=( --network "$DOCKER_NETWORK" )

  # If ./world folder exists on host, bind-mount it too
  # (Migrated: we now mount the whole ./data to /data, so world is included)
  
  docker run --rm "${net_args[@]}" \
    -u "${TARGET_UID}:${TARGET_GID}" \
    -e RESTIC_HOSTNAME="$RESTIC_HOSTNAME" \
    -e RESTIC_PASSWORD="$RESTIC_PASSWORD" \
    -e RESTIC_REPOSITORY="$RESTIC_REPOSITORY" \
    -e RCLONE_CONFIG="$RCLONE_CONF_CONT" \
    -e XDG_CACHE_HOME="/data/.cache" \
    -v "$PROJECT_ROOT/data":/data \
    -v "$RCLONE_CONF_HOST":"$RCLONE_CONF_CONT":ro \
    "$RESTIC_IMAGE" -r "$RESTIC_REPOSITORY" "$@"
}

# Checks if the Minecraft container is running
mc_is_running() {
  docker ps --format '{{.Names}} {{.Status}}' \
    | grep -E "^${MC_CONTAINER_NAME}\b" | grep -qi 'Up'
}

# --- Functions (corresponding to original scripts) ---

# ex exec_restic.sh
# Executes raw restic commands
exec_restic() {
  if [[ $# -eq 0 ]]; then
    echo "[ERROR] usage: exec_restic <args...>  (restic arguments)"
    return 2
  fi
  echo "[INFO] Executing: restic $*"
  docker_restic "$@"
}

# ex unlock-repo.sh
# Unlocks the restic repository
unlock_repo() {
  echo "[INFO] Unlocking repository: $RESTIC_REPOSITORY (hostname=$RESTIC_HOSTNAME)"
  docker_restic unlock --remove-all
  echo "[OK] Unlock completed."
}

# ex update-world-offline.sh
# Restores the world from a snapshot
restore_world_offline() {
  local snapshot="${1:-latest}"
  echo "[INFO] Restore '${snapshot}' to / (restores absolute paths, e.g. /data/world) host=$RESTIC_HOSTNAME"
  docker_restic restore "$snapshot" --target / --host "$RESTIC_HOSTNAME" --no-lock
  echo "[OK] Restore completed."
}

# ex backup-world-offline.sh
# Backs up the world to the repository
backup_world_offline() {
  if mc_is_running; then
    echo "[ERROR] MC container '${MC_CONTAINER_NAME}' is running. Stop it for OFFLINE backup."
    return 3
  fi

  # Build multiple --tag from RESTIC_TAG
  local TAG_ARGS=()
  IFS=',' read -r -a _tags <<< "$RESTIC_TAG"
  for t in "${_tags[@]}"; do
    t="$(echo "$t" | xargs)"
    [[ -n "$t" ]] && TAG_ARGS+=( --tag "$t" )
  done

  echo "[INFO] Starting backup of /data/world with tags: ${_tags[*]:-"<none>"}"
  docker_restic backup "${TAG_ARGS[@]}" -vv --host "$RESTIC_HOSTNAME" /data/world
  echo "[OK] Backup completed."
}

# Initializes the restic repository
init_repo() {
  echo "[INFO] Initializing repository: $RESTIC_REPOSITORY (host=$RESTIC_HOSTNAME)"
  docker_restic init
  echo "[OK] Repo initialized."
}

# Checks the health of the repository connection
doctor() {
  echo "[INFO] Check rclone.conf @ $RCLONE_CONF_HOST -> $RCLONE_CONF_CONT"
  [[ -s "$RCLONE_CONF_HOST" ]] || { echo "[ERROR] rclone.conf missing or empty"; return 2; }
  echo "[INFO] Trying 'restic snapshots'..."
  docker_restic snapshots || { echo "[ERROR] Repo access failed"; return 3; }
  echo "[OK] Repo connection OK."
}

# --- CLI dispatcher (convenient) ---
usage() {
  cat <<EOF
Usage:
  $(basename "$0") exec <args...>       # executes 'restic <args...>'
  $(basename "$0") unlock               # unlocks locks (--remove-all)
  $(basename "$0") restore [SNAPSHOT]   # default: latest
  $(basename "$0") backup               # OFFLINE backup of /data/world
  $(basename "$0") init                 # initializes Restic repository
  $(basename "$0") doctor               # checks repo access (snapshots)

Equivalent bash functions:
  source $(basename "$0")
  exec_restic <args...>
  unlock_repo
  restore_world_offline [SNAPSHOT]
  backup_world_offline

Variables (env/.env):
  RESTIC_HOSTNAME   (default: Mondo)
  RESTIC_PASSWORD   (REQUIRED)
  RESTIC_REPOSITORY (REQUIRED, e.g.: rclone:mega:/modpack)
  RCLONE_CONF_HOST  (default: ./env/rclone.conf)
  RESTIC_IMAGE      (default: docker.io/tofran/restic-rclone:0.17.0_1.68.2)

  MC_CONTAINER_NAME (default: modpack)
  RESTIC_TAG       (CSV, default: mc_backups)
  DOCKER_NETWORK    (optional)
EOF
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  cmd="${1:-}"; shift || true
  case "$cmd" in
    exec)    exec_restic "$@" ;;
    unlock)  unlock_repo ;;
    restore|update|update-world) restore_world_offline "${1:-latest}" ;;
    backup|backup-world) backup_world_offline ;;
    init)    init_repo ;;
    doctor)  doctor ;;
    ""|help|-h|--help) usage ;;
    *) echo "[ERROR] Unknown command: $cmd"; usage; exit 1 ;;
  esac
fi
