#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./run-server.sh            # auto mode: restore profile
#   ./run-server.sh            # auto mode: restore profile
#   ./run-server.sh restoreoff # start without restore
#   ./run-server.sh -d         # detach mode

# ========= Helpers =========
# Helper functions for logging
mkdir -p ./logs
LOG_FILE="./logs/startup.log"
# Initialize log file
if [[ ! -f "$LOG_FILE" ]]; then touch "$LOG_FILE"; fi

log()  {
  if [[ "${DETACH:-false}" == "true" ]]; then
      # In detached mode, log only to file (silent startup)
      echo "[INFO] $*" >> "$LOG_FILE"
  else
      # Normal mode: tee to stdout and file
      echo "[INFO] $*" | tee -a "$LOG_FILE"
  fi
}
warn() { echo "[WARN] $*" | tee -a "$LOG_FILE" >&2; }
err()  { echo "[ERROR] $*" | tee -a "$LOG_FILE" >&2; exit 1; }

# Helper to remove files robustly (try normal rm, then sudo rm)
robust_rm() {
  local file="$1"
  if [[ -f "$file" ]]; then
      log "Removing $file..."
      rm -f "$file" 2>/dev/null || true
      if [[ -f "$file" ]]; then
          log "Normal remove failed for $file. Trying sudo..."
          sudo rm -f "$file" || warn "Failed to remove $file with sudo."
      fi
  fi
}

# Source .env file
if [ -f "env/.env" ]; then
    # Using 'set -a' so that sourced variables are exported to the environment
    set -a
    source "env/.env"
    set +a
else
    err ".env file not found in env/.env! Run ./install_and_configure.sh first."
fi

# Source mod-specific functions
if [ -f "./utils/mods_options.sh" ]; then
    source "./utils/mods_options.sh"
fi

# ========= Docker Check =========
# Checks if Docker is running
check_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    err "Docker is not installed. Please install Docker and try again."
  fi

  if ! docker info >/dev/null 2>&1; then
    err "Docker is not running. Please start Docker Desktop and try again."
  fi
}

# ========= Config / Env =========
# Loads the .env file and sets default values
load_env() {
  [[ -f ./env/.env ]] || err "env/.env mancante"
  set -a
  # Warning: .env must be valid, e.g. MOTD quoted if containing spaces/special symbols
  source ./env/.env
  set +a

  # Container UID/GID (default 1000:1000)
  export TARGET_UID="${UID:-$(id -u)}"
  export TARGET_GID="${GID:-$(id -g)}"

  # Default for rclone mutex (can be overridden in .env)
  : "${CLOUD_MUTEX_DIR:=/Root/modpack}"          # /Root/<dir> in MEGA (e.g. /Root/modpack)
  : "${MUTEX_FILE:=mutex.txt}"                   # flag file name
  : "${RCLONE_CONF_HOST:=./env/rclone.conf}"     # rclone.conf path on host
  : "${CLOUD_MUTEX_KEEPALIVE:=1}"                # 1 = update mtime periodically
  : "${CLOUD_MUTEX_PULSE:=60}"                   # keepalive interval in seconds

  # Rclone mutex script (must exist and be executable)
  : "${RCLONE_MUTEX_SH:=./utils/rclone-mutex.sh}"
  PRELOAD_ROOT="${PRELOAD_ROOT:-./overrides}"       # local source to "preload"
  PRELOAD_EXCLUDES="${PRELOAD_EXCLUDES:-}"     # e.g.: 'tmp cache *.bak .DS_Store'
}

# ========= Bind mounts permissions =========
ensure_permissions() {
  log "Checking/fixing permissions on ./data"
  mkdir -p ./data

  # Fix permissions for the whole data directory
  # Optimize: Only chown if owner/group is different
  find "./data" \( ! -user "${TARGET_UID}" -o ! -group "${TARGET_GID}" \) -exec chown "${TARGET_UID}:${TARGET_GID}" {} + 2>/dev/null || {
      warn "Conditional chown on ./data failed, retrying with sudo..."
      sudo find "./data" \( ! -user "${TARGET_UID}" -o ! -group "${TARGET_GID}" \) -exec chown "${TARGET_UID}:${TARGET_GID}" {} + 2>/dev/null || \
        warn "chown ./data failed even with sudo."
  }

  # Optimize: Only chmod if permissions are different
  find "./data" -type d ! -perm 775 -exec chmod 775 {} + 2>/dev/null || sudo find "./data" -type d ! -perm 775 -exec chmod 775 {} +

  # stale world lock
  rm -f ./data/world/session.lock 2>/dev/null || sudo rm -f ./data/world/session.lock 2>/dev/null || true

  # check writability
  if ! test -w ./data ; then
    err "./data is not writable. Check owner/permissions."
  fi
}

# ========= Sync host -> data =========
# Syncs a local directory into the data directory (simple copy now)
sync_into_data() {
  local src_dir="$1"      # es: config
  local dest_sub="$2"     # es: config
  
  if [[ -d "./${src_dir}" ]]; then
    echo "[INFO] Sync ${src_dir}/ -> ./data/${dest_sub}"
    mkdir -p "./data/${dest_sub}"
    cp -r "./${src_dir}/." "./data/${dest_sub}/" 2>/dev/null || true
    # permissions fixed by ensure_permissions later or we fix here
    chown -R "${TARGET_UID}:${TARGET_GID}" "./data/${dest_sub}"
  else
    echo "[INFO] ${src_dir}/ not found, skipping sync."
  fi
}

preload_into_data() {
  local root="$1"
  local excludes_str="$2"
  echo "[INFO] Preloading from $root (Optimized: single container)"
  [[ -d "$root" ]] || { echo "[INFO] $root does not exist, skipping."; return; }

  # Run a single alpine container to handle all copies
  # We pass the excludes string as env var
  # We mount local ./data to /data in container
  docker run --rm -u 0 \
    -e DST_ROOT="/data" -e UID="${TARGET_UID}" -e GID="${TARGET_GID}" \
    -e EXCLUDES="$excludes_str" \
    -v "$(pwd)/data":/data \
    -v "$(pwd)/$root":/mnt/src:ro \
    alpine:3.20 sh -c '
      set -u
      cd /mnt/src || exit 1
      
      # Iterate over all files/dirs in /mnt/src
      for item in *; do
        [ -e "$item" ] || continue
        
        # Check exclusion
        skip=0
        for pat in $EXCLUDES; do
           # Shell glob matching
           case "$item" in
             $pat) skip=1; break ;;
           esac
        done
        
        if [ "$skip" -eq 1 ]; then
           echo "[Container] Skip $item (matched exclude)"
           continue
        fi

        echo "[Container] Copying $item..."
        if [ -d "$item" ]; then
           mkdir -p "$DST_ROOT/$item"
           cp -a "$item/." "$DST_ROOT/$item/"
        else
           cp -a "$item" "$DST_ROOT/"
        fi
        
        # Fix permissions
        chown -R "$UID:$GID" "$DST_ROOT/$item"
      done
    ' || echo "[WARN] Preload failed"
}

# ========= Prompt backup offline =========
# Asks the user if they want to perform an offline backup
prompt_backup() {
  # Usage: prompt_backup <default:y|n>
  local def="${1:-n}" # implicit default: NO
  local prompt="Do you want to backup the current Minecraft world? "
  if [[ "$def" == [Yy] ]]; then
    prompt+="(Y/n): "
  else
    prompt+="(y/N): "
  fi
  while true; do
    read -p "$prompt" user_input
    user_input=${user_input:-$def}
    case "$user_input" in
      y|Y) log "Backup requested."; return 0 ;;
      n|N) log "Backup skipped.";   return 1 ;;
      *)   warn "Please enter 'y' or 'n'." ;;
    esac
  done
}

# Performs the offline backup using restic-tools.sh
do_offline_backup() {
  log "Performing offline backup..."
  
  if type optimize_mod_data >/dev/null 2>&1; then
      optimize_mod_data
  fi

  bash ./utils/restic-tools.sh backup

  log "Performing Cloud Data Sync (Rclone ./data -> Mega)..."
  bash ./utils/cloud-sync.sh sync || warn "Cloud sync failed!"
}

# Performs only world backup (no server data sync)
do_world_backup_only() {
  log "Performing offline backup (WORLD ONLY)..."
  
  if type optimize_mod_data >/dev/null 2>&1; then
      optimize_mod_data
  fi

  bash ./utils/restic-tools.sh backup
}

# ========= Cloud Mutex (rclone → mega:/<dir>/mutex.txt) =========
# Derives the remote directory path for the mutex file
derive_mutex_remote_dir() {
  # Priority: explicit MUTEX_REMOTE_DIR > derivation from RESTIC_REPOSITORY+CLOUD_MUTEX_DIR
  if [[ -n "${MUTEX_REMOTE_DIR:-}" ]]; then
    echo "${MUTEX_REMOTE_DIR}"
    return
  fi
  # Derive remote (e.g. 'mega') from RESTIC_REPOSITORY=rclone:<remote>:/repo
  local repo="${RESTIC_REPOSITORY#rclone:}"   # mega:/something
  local remote="${repo%%:*}"                  # mega
  local sub="${CLOUD_MUTEX_DIR#/Root}"        # /
  sub="${sub#/}"                              # strip leading /
  echo "${remote}:/${sub}"
}



# Ensures the mutex exists on the cloud
cloud_mutex_prepare() {
  if [[ ! -x "${RCLONE_MUTEX_SH}" ]]; then
    warn "Mutex script not found or not executable: ${RCLONE_MUTEX_SH}. Proceeding without ensure."
    return 0
  fi
  export MUTEX_REMOTE_DIR="$(derive_mutex_remote_dir)"
  export RCLONE_CONF_HOST
  export MUTEX_FILE
  log "Cloud mutex ensure on ${MUTEX_REMOTE_DIR}/${MUTEX_FILE} ..."
  if [[ "${DETACH:-false}" == "true" ]]; then
      "${RCLONE_MUTEX_SH}" ensure >> "$LOG_FILE" 2>&1
  else
      "${RCLONE_MUTEX_SH}" ensure
  fi
}


# Releases the cloud mutex
cloud_mutex_release() {
  if [[ ! -x "${RCLONE_MUTEX_SH}" ]]; then
    return 0
  fi
  export MUTEX_REMOTE_DIR="$(derive_mutex_remote_dir)"
  export RCLONE_CONF_HOST
  export MUTEX_FILE
  log "Cloud mutex release on ${MUTEX_REMOTE_DIR}/${MUTEX_FILE} ..."
  if [[ "${DETACH:-false}" == "true" ]]; then
      "${RCLONE_MUTEX_SH}" release >> "$LOG_FILE" 2>&1
  else
      "${RCLONE_MUTEX_SH}" release
  fi
}

# ========= Auto-Confirm FML =========
auto_fml_confirm() {
  log "DEBUG: Starting auto-confirm monitor (waiting for container)..."
  local container_name="${MC_CONTAINER_NAME}"
  
  # 1. Wait for container to start (max 60s)
  local retries=0
  until docker ps --format '{{.Names}}' | grep -q "^${container_name}$"; do
    sleep 2
    ((retries++))
    if [ $retries -gt 30 ]; then return; fi
  done

  # 2. Monitor logs for 2 minutes
  for i in {1..24}; do
    # Search for specific string in recent logs
    if docker logs "${container_name}" --tail 100 2>&1 | grep -q "Run the command /fml confirm"; then
       log "[!] FML REQUEST DETECTED! Sending '/fml confirm' automatically..."
       
       # SEND COMMAND VIA PIPE TO ATTACH
       # This sends text to container stdin without "entering" it
       echo "/fml confirm" | docker attach "${container_name}"
       
       log "[Command sent.]"
       return 0
    fi
    sleep 5
  done
  log "[DEBUG] No FML request detected after 2 minutes."
}


# ========= Start docker-compose =========
# Starts the Docker Compose services
compose_up() {
  local mode="${1:-auto}"  # auto | restoreon | restoreoff
  local scale_args=""
  
  if [[ "${BACKUP:-true}" == "false" ]]; then
     log "BACKUP=false -> Disabling backups container."
     scale_args="--scale backups=0"
  fi

  log "Starting Minecraft..."
  case "$mode" in
    restoreoff)
      log "Starting without restore from cloud storage..."
      update_mods_list
      # Use --exit-code-from mc so that if mc stops (AutoStop), backups container is also stopped.
      # shellcheck disable=SC2086
      docker compose --env-file env/.env up --build --exit-code-from mc $scale_args
      ;;
    restoreon|auto|*)
      if [[ "${BACKUP:-true}" == "false" ]]; then
          if [[ "$mode" == "restoreon" ]]; then
               log "BACKUP=false but restoreon requested -> Forcing restore attempt."
               # Ensure MUTEX_REMOTE_DIR is set (it might not be if cloud_mutex_prepare was skipped)
               if [[ -z "${MUTEX_REMOTE_DIR:-}" ]]; then
                   export MUTEX_REMOTE_DIR="$(derive_mutex_remote_dir)"
               fi
          else
               log "BACKUP=false -> FORCE restoreoff (default behavior when backup is disabled)."
               log "Skipping restore step because BACKUP=false."
               # Force mode to restoreoff to skip the restore block
               mode="restoreoff"
          fi
      fi

      if [[ "$mode" != "restoreoff" ]]; then
          log "Mode ${mode} -> using restore profile."
          
          # --- SMART RESTORE CHECK ---
          # Run a temp container to check timestamps (since we can't do it on host easily if restic is missing)
          # Only if we have a local world to compare
          if [[ -f "./world/level.dat" ]]; then
             log "Checking for Smart Restore (Local vs Cloud timestamps)..."
             # We use the same image as restore-backup service
             IMG="${RESTIC_IMAGE:-docker.io/tofran/restic-rclone:0.17.0_1.68.2}"
             
             # Get Cloud Timestamp (JSON parsing via grep/sed since jq might be missing)
             # We mount rclone config. We don't need to mount world, just read metadata.
             # We assume default values from .env are exported.
             
             # Capture output. We use --json to get precise time.
             # We need to pass env vars.
             # We must override entrypoint because the image has a custom one.
             json_out=$(docker run --rm --entrypoint "" --env-file env/.env \
                -v "$(pwd)/env/rclone.conf:${RCLONE_CONFIG}:ro" \
                "$IMG" restic -r "$RESTIC_REPOSITORY" snapshots --host "$RESTIC_HOSTNAME" --latest 1 --json 2>/dev/null || true)
             
             # Parse time: "time":"2026-02-10T16:28:01.123456789+00:00"
             # grep -o matches only the part.
             cloud_time_str=$(echo "$json_out" | grep -o '"time":"[^"]*"' | cut -d'"' -f4 | head -n1 || true)
             
             if [[ -n "$cloud_time_str" ]]; then
                 # Convert to epoch. 'date' in alpine/busybox (in container) or host?
                 # Host 'date' is usually GNU date on Linux, which handles ISO8601.
                 cloud_ts=$(date -d "$cloud_time_str" +%s 2>/dev/null || echo 0)
                 
                 # Local timestamp
                 local_ts=$(stat -c %Y ./world/level.dat 2>/dev/null || echo 0)
                 
                 log "Smart Restore: Local=$(date -d @$local_ts), Cloud=$(date -d @$cloud_ts)"
                 
                 if [[ "$local_ts" -gt "$cloud_ts" ]]; then
                     if [[ "$mode" == "restoreon" ]]; then
                         log ">>> Local world is NEWER than cloud, but 'restoreon' was requested. FORCING RESTORE."
                     else
                         log ">>> Local world is NEWER than cloud. SKIPPING RESTORE (Smart Restore)."
                         RESTORE_MODE="restoreoff"
                         # We must break/skip the restore block below
                         mode="restoreoff" 
                     fi
                 else
                     log "Cloud is newer or same. Proceeding with restore."
                 fi
             else
                 warn "Could not fetch/parse cloud snapshot time. Proceeding with standard restore."
             fi
          fi
          # ---------------------------
          
          if [[ "$mode" != "restoreoff" ]]; then
              # [NEW] Restore data/ from cloud (excluding world)
              log "Pre-restore: Syncing data from cloud (run-server/cloud-sync)..."
              bash ./utils/cloud-sync.sh restore

              # 1. Execute Restore (blocks until finish)
              # We target ONLY restore-backup service.
              docker compose -f docker-compose.yml -f ./images/minecraft-server/docker-compose.restore-overrides.yml \
                --profile restore --env-file env/.env up --build restore-backup

              log "Post-restore: Fixing permissions..."
              ensure_permissions
              
              log "Post-restore: Enforcing clean OP list (removing restored ops.json)..."
              log "Post-restore: Enforcing clean OP list (removing restored ops.json)..."
              robust_rm ./data/ops.json
              robust_rm ./data/usercache.json
          fi
      fi

      # 2. Main Start
      # We do NOT include the restore-overrides (dependencies) nor the restore profile.
      # This avoids "container stopped" abort triggers from the completed restore service.
      log "Restore completed (or skipped). Starting Server..."
      update_mods_list
      # shellcheck disable=SC2086
      if [[ "${DETACH:-false}" == "true" ]]; then
          log "Server run in Detatch mode!"
          docker compose -f docker-compose.yml --env-file env/.env up -d --build $scale_args > ./logs/compose-up.log 2>&1
      else
          docker compose -f docker-compose.yml --env-file env/.env up --build --exit-code-from mc $scale_args
      fi
      ;;
  esac
}

# --- Dynamic Dockerfile Selection ---
# Version comparison logic
version_ge() {
  local version_actual="$1"
  local version_required="$2"
  local lowest
  lowest="$(printf '%s\n%s' "$version_actual" "$version_required" | sort -V | head -n1)"
  [[ "$lowest" == "$version_required" ]]
}

# ========= Main =========
# Main entry point
main() {
  check_docker
  load_env

  # Parse arguments FIRST to set flags like DETACH
  BACKUP="${BACKUP:-true}"
  RESTORE_MODE="auto"
  DETACH="false"
  
  for arg in "$@"; do
    case "$arg" in
      -d|--detach)
        DETACH="true"
        # BACKUP remains true by default unless explicitly disabled, so backups container runs
        ;;
      --backupoff)
        BACKUP=false
        # We can't log yet if we haven't loaded env/log function? No, log is defined above functions.
        # But we haven't loaded .env yet?
        # Actually log definition doesn't depend on env.
        ;;
      --restoreoff)
        RESTORE_MODE="restoreoff"
        ;;
      --restoreon)
        RESTORE_MODE="restoreon"
        ;;
      --loadcurrbackup | --loadcurrserver)
        # This is handled in the backup block below
        ;;
      --loadcurrworld)
        # Handled below
        ;;
      *)
        # Assume valid for other uses or standard main arg logic
        ;;
    esac
  done
  export BACKUP

  if [[ "$BACKUP" == "false" ]]; then
      log "Mode: backupoff -> Backups DISABLED (cloud & local)."
  fi
  if [[ "$RESTORE_MODE" == "restoreoff" ]]; then
      log "Mode: restore off -> Restore from cloud storage DISABLED."
  fi
  
  if [[ -n "${VERSION:-}" ]]; then
      # 1.20.5 - 1.21+ (Attuale) -> Java 21
      if version_ge "$VERSION" "1.20.5"; then
          log "Minecraft version $VERSION detected (>= 1.20.5). Using mcserver.java21.Dockerfile (Java 21). Note: Java 17 would crash."
          export MC_DOCKERFILE="mcserver.java21.Dockerfile"
      
      # 1.18 - 1.20.4 -> Java 17
      # Note: 1.17 required Java 16, but we use 17 (LTS).
      elif version_ge "$VERSION" "1.17.0"; then
          log "Minecraft version $VERSION detected (>= 1.17.0). Using mcserver.java17.Dockerfile (Java 17)."
          export MC_DOCKERFILE="mcserver.java17.Dockerfile"
      
      # 1.16.5 and older -> Java 8
      else
          log "Minecraft version $VERSION detected (< 1.17.0). Using mcserver.java8.Dockerfile (Java 8). Note: Newer Java versions may crash."
          export MC_DOCKERFILE="mcserver.java8.Dockerfile"
      fi
  else
      log "VERSION not set, defaulting to mcserver.java21.Dockerfile"
      export MC_DOCKERFILE="mcserver.java21.Dockerfile"
  fi

  # Delete all Zone.Identifier
  echo ">>> Removing all Zone.Identifier files..."
  bash ./utils/delete-all-zone-identifier.sh

  log "Preflight permissions..."
  ensure_permissions
  
  if [[ "${DETACH:-false}" == "true" ]]; then
      preload_into_data "$PRELOAD_ROOT" "$PRELOAD_EXCLUDES" >> "$LOG_FILE" 2>&1
  else
      preload_into_data "$PRELOAD_ROOT" "$PRELOAD_EXCLUDES"
  fi
  # Clean up ephemeral alpine image immediately as requested
  # docker rmi alpine:3.20 2>/dev/null || true

  # Force clean ops.json to ensure fresh UUID generation via RCON
  log "Enforcing clean OP list: removing ./data/ops.json..."
  log "Enforcing clean OP list: removing ./data/ops.json..."
  robust_rm ./data/ops.json
  robust_rm ./data/usercache.json

  # Mutex before any operation (avoids multi-host race)
  if [[ "$BACKUP" == "true" ]]; then
      cloud_mutex_prepare
  else
      log "BACKUP=false -> Skip Cloud Mutex Prepare."
  fi

  # Offline backup BEFORE start
  # Updated rules:
  # - BACKUP=false: SKIP
  # - No args: NO prompt -> skip backup and start immediately
  # - Arg 'loadcurrbackup': forced backup without prompt
  # - Any other arg (except switches): prompt with default 'y'
  if [[ "$BACKUP" == "false" ]]; then
      log "BACKUP=false -> Skipping offline backup."
  elif [[ $# -eq 0 ]]; then
    log "No args -> skipping backup without prompt."
  elif [[ "$*" == *"loadcurrbackup"* || "$*" == *"loadcurrserver"* ]]; then 
    log "Arg 'loadcurrbackup' or 'loadcurrserver' -> performing FULL backup without prompt."
    do_offline_backup
  elif [[ "$*" == *"loadcurrworld"* ]]; then # Check if loadcurrworld is present in args
      log "Arg 'loadcurrworld' -> performing WORLD backup ONLY without prompt."
      do_world_backup_only
  elif [[ "$DETACH" == "true" ]]; then
      log "Detached mode -> skipping manual backup prompt."
  else 
      # Logic from before was: argument present -> prompt backup.
      # If argument is 'restoreoff', it triggered prompt.
      # Let's maintain that behavior unless backupoff.
      if prompt_backup "n"; then
        do_offline_backup
      else
        log "Starting without backup."
      fi
  fi
  
  # Start FML monitor in background
  auto_fml_confirm > ./logs/fml-confirm.log 2>&1 &

  # Start with/without restore
  # Run auto-op in background redirecting log
  # Start with/without restore
  # Run auto-op in background redirecting log
  auto_op_users > ./logs/auto-op.log 2>&1 &
  auto_clean_souls > ./logs/auto-clean-souls.log 2>&1 &
  
  # --- TRAP for Shutdown Backup ---
  # If the script is interrupted (Ctrl+C), we want to:
  # 1. Stop the docker-compose (gracefully)
  # 2. Perform offline backup (if BACKUP=true)
  # 3. Cleanup
  
  cleanup() {
    log "Trapped signal or normal exit. Shutting down..."
    # Stop containers (if running attached, compose_up might have already exited, but safe to run)
    docker compose stop
    
    # Offline backup on shutdown?
    if [[ "$BACKUP" == "true" ]]; then
      log "Performing Backup on Shutdown (Offline)..."
      do_offline_backup || warn "Backup on shutdown failed!"
    fi

    # Kill background jobs (auto_fml_confirm, auto_op_users, auto_clean_souls)
    # We use 'jobs -p' to find them. 
    # Suppress error if no jobs running.
    # We must do this to allow 'wait' to return if it was waiting on them.
    local pids=$(jobs -p)
    if [[ -n "$pids" ]]; then
      log "Killing background jobs: $pids"
      kill $pids 2>/dev/null || true
      wait $pids 2>/dev/null || true
    fi

    cloud_mutex_release
    log "Cleanup complete. Bye."
    # Explicit exit to ensure we don't continue script execution if called from trap
    exit 0
  }
  
  # Trap SIGINT (Ctrl+C) and SIGTERM. 
  # We do NOT trap EXIT here because it would trigger twice (once on signal, once on exit).
  # Or we can trap EXIT and check if we already cleaned up?
  # Standard pattern: trap cleanup EXIT (covers all). 
  # But 'docker compose' also traps signals.
  # Let's use EXIT and ensure idempotency if needed, or just EXIT.
  # If we trap SIGINT, we must exit manually.
  trap cleanup EXIT

  # Run compose attached
  # If user presses Ctrl+C here, trap triggers.
  # If compose exits normally (e.g. server stop command), we proceed to next lines?
  # Actually, if we use 'set -e', any error triggers EXIT trap.
  
  # We use a subshell or allow failure to handling trap properly? 
  # Actually 'docker compose up' will take over signal handling if attached.
  # But if we Ctrl+C, bash receives it too.
  
  # Let's simple run it.
  compose_up "$RESTORE_MODE" || true
  
  if [[ "$DETACH" == "true" ]]; then
      # Clear trap to prevent shutdown
      trap - EXIT
      # Explicitly echo to stdout even in detached mode as user requested this specific message
      echo "[INFO] Detached start complete. Server is running in background."
      exit 0
  fi

  
  # Explicitly remove trap to avoid double execution if we reached here normally?
  # No, 'EXIT' trap runs on normal exit too. So we just let it run.
  # But we might want to distinguish if we already did it?
  # The trap function acts as the "Shutdown & Backup" phase.


}

main "$@"
