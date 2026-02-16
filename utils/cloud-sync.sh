#!/bin/bash
set -euo pipefail

# Usage: ./utils/cloud-sync.sh [sync|restore]

# --- Find project root and ENV ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [[ -f "$SCRIPT_DIR/env/.env" ]]; then
  PROJECT_ROOT="$SCRIPT_DIR"
  ENV_FILE="$SCRIPT_DIR/env/.env"
elif [[ -f "$SCRIPT_DIR/../env/.env" ]]; then
  PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
  ENV_FILE="$PROJECT_ROOT/env/.env"
else
  echo "[ERROR] env/.env not found"
  exit 1
fi
cd "$PROJECT_ROOT"

# --- Load ENV ---
set -a
source "$ENV_FILE"
set +a

# --- Check Config ---
RCLONE_CONF_HOST="${RCLONE_CONF_HOST:-./env/rclone.conf}"
[[ -f "$RCLONE_CONF_HOST" ]] || { echo "[ERROR] rclone.conf missing"; exit 1; }

# Derive Remote and Path from RESTIC_REPOSITORY if not explicitly set
# RESTIC_REPOSITORY example: rclone:mega:/modpack
# We want to sync to mega:/modpack/data (or similar)
if [[ -z "${CLOUD_SYNC_TARGET:-}" ]]; then
    # Strip 'rclone:' prefix
    repo="${RESTIC_REPOSITORY#rclone:}"
    # This is likely 'mega:/modpack'
    # We append '/server-data' to keep it separate from restic repo files
    CLOUD_SYNC_TARGET="${repo}/server-data"
fi

RESTIC_IMAGE="${RESTIC_IMAGE:-docker.io/tofran/restic-rclone:0.17.0_1.68.2}"

COMMAND="${1:-sync}"

# Default UID/GID if not set (e.g. running manually)
: "${TARGET_UID:=$(id -u)}"
: "${TARGET_GID:=$(id -g)}"

echo "[INFO] Cloud Sync Target: ${CLOUD_SYNC_TARGET}"
echo "[INFO] Command: ${COMMAND}"

if [[ "$COMMAND" == "sync" ]]; then
    echo "[INFO] Syncing ./data -> ${CLOUD_SYNC_TARGET} (excluding world/)"
    # We use a docker container for rclone to ensure environment consistency
    # Mount config to default location for root user
    docker run --rm --entrypoint "" \
        -u "${TARGET_UID}:${TARGET_GID}" \
        -v "$PROJECT_ROOT/data":/data:ro \
        -e RCLONE_CONFIG="${RCLONE_CONFIG:-/root/.config/rclone/rclone.conf}" \
        -e XDG_CACHE_HOME="/tmp/.cache" \
        -v "$RCLONE_CONF_HOST":${RCLONE_CONFIG:-/root/.config/rclone/rclone.conf}:ro \
        "$RESTIC_IMAGE" \
        rclone sync /data "${CLOUD_SYNC_TARGET}" \
        --exclude "/world/**" \
        --exclude "/session.lock" \
        --exclude "/.cache/**" \
        --progress \
        --create-empty-src-dirs
    echo "[OK] Sync complete."

elif [[ "$COMMAND" == "check" ]]; then
    echo "[INFO] Checking sync status (Dry Run)..."
    docker run --rm --entrypoint "" \
        -u "${TARGET_UID}:${TARGET_GID}" \
        -v "$PROJECT_ROOT/data":/data:ro \
        -e RCLONE_CONFIG="${RCLONE_CONFIG:-/root/.config/rclone/rclone.conf}" \
        -e XDG_CACHE_HOME="/tmp/.cache" \
        -v "$RCLONE_CONF_HOST":${RCLONE_CONFIG:-/root/.config/rclone/rclone.conf}:ro \
        "$RESTIC_IMAGE" \
        rclone sync /data "${CLOUD_SYNC_TARGET}" \
        --exclude "/world/**" \
        --exclude "/session.lock" \
        --exclude "/.cache/**" \
        --dry-run \
        --verbose
    echo "[OK] Check complete."

elif [[ "$COMMAND" == "restore" ]]; then
    echo "[WARN] Restore requested. This will OVERWRITE local data (excluding world)."
    echo "Press Ctrl+C to cancel or wait 5s..."
    sleep 5
    
    docker run --rm --entrypoint "" \
        -u "${TARGET_UID}:${TARGET_GID}" \
        -v "$PROJECT_ROOT/data":/data \
        -e RCLONE_CONFIG="${RCLONE_CONFIG:-/root/.config/rclone/rclone.conf}" \
        -e XDG_CACHE_HOME="/data/.cache" \
        -v "$RCLONE_CONF_HOST":${RCLONE_CONFIG:-/root/.config/rclone/rclone.conf}:ro \
        "$RESTIC_IMAGE" \
        rclone sync "${CLOUD_SYNC_TARGET}" /data \
        --exclude "/world/**" \
        --exclude "/.cache/**" \
        --progress
    echo "[OK] Restore complete."
else
    echo "Usage: $0 [sync|restore]"
    exit 1
fi
