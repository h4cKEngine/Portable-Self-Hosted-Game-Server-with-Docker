#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./run-server.sh            # auto mode: restore profile
#   ./run-server.sh restoreoff # start without restore

# ========= Helpers =========
# Helper functions for logging
log()  { echo "[INFO] $*"; }
warn() { echo "[WARN] $*" >&2; }
err()  { echo "[ERROR] $*" >&2; exit 1; }

# ========= Config / Env =========
# Loads the .env file and sets default values
load_env() {
  [[ -f ./env/.env ]] || err "env/.env mancante"
  set -a
  # Warning: .env must be valid, e.g. MOTD quoted if containing spaces/special symbols
  source ./env/.env
  set +a

  # Container UID/GID (default 1000:1000)
  TARGET_UID="${UID:-1000}"
  TARGET_GID="${GID:-1000}"

  # Default for rclone mutex (can be overridden in .env)
  : "${CLOUD_MUTEX_DIR:=/Root/modpack}"          # /Root/<dir> in MEGA (e.g. /Root/modpack)
  : "${MUTEX_FILE:=mutex.txt}"                   # flag file name
  : "${RCLONE_CONF_HOST:=./env/rclone.conf}"     # rclone.conf path on host
  : "${CLOUD_MUTEX_KEEPALIVE:=1}"                # 1 = update mtime periodically
  : "${CLOUD_MUTEX_PULSE:=60}"                   # keepalive interval in seconds

  # Rclone mutex script (must exist and be executable)
  : "${RCLONE_MUTEX_SH:=./utils/rclone-mutex.sh}"
  PRELOAD_ROOT="${PRELOAD_ROOT:-./data}"       # local source to "preload"
  PRELOAD_EXCLUDES="${PRELOAD_EXCLUDES:-}"     # e.g.: 'tmp cache *.bak .DS_Store'
}

# ========= Volume =========
# Creates the Docker volume if it doesn't exist
ensure_volume() {
  if ! docker volume inspect "${VOLUME_NAME}" &>/dev/null; then
    log "Volume '${VOLUME_NAME}' non trovato. Lo creo..."
    docker volume create "${VOLUME_NAME}" >/dev/null
  else
    log "Volume '${VOLUME_NAME}' già esistente."
  fi
}

# ========= Bind mounts permissions =========
ensure_permissions() {
  log "Checking/fixing permissions on world/ and mods/"
  for d in world mods; do
    mkdir -p "./$d"

    chown -R "${TARGET_UID}:${TARGET_GID}" "./$d" 2>/dev/null || {
      warn "chown $d to ${TARGET_UID}:${TARGET_GID} without sudo failed, retrying with sudo..."
      sudo chown -R "${TARGET_UID}:${TARGET_GID}" "./$d" 2>/dev/null || \
        warn "chown $d failed even with sudo. Fix permissions manually if needed."
    }

    find "./$d" -type d -exec chmod 775 {} \; 2>/dev/null || sudo find "./$d" -type d -exec chmod 775 {} \;
    find "./$d" -type f -exec chmod 664 {} \; 2>/dev/null || sudo find "./$d" -type f -exec chmod 664 {} \;
  done

  # stale world lock
  rm -f ./world/session.lock 2>/dev/null || sudo rm -f ./world/session.lock 2>/dev/null || true

  # check writability
  if ! test -w ./world ; then
    err "./world is not writable. Check owner/permissions (root:root?)."
  fi
}

# ========= Sync host -> volume =========
# Syncs a local directory into the Docker volume
sync_into_volume() {
  local src_dir="$1"      # es: config
  local dest_sub="$2"     # es: config
  local img
  # use an existing image (restic-rclone); fallback to alpine only if locally present
  img="${RESTIC_IMAGE:-docker.io/tofran/restic-rclone:0.17.0_1.68.2}"
  if [[ -d "./${src_dir}" ]]; then
    echo "[INFO] Sync ${src_dir}/ -> volume:/data/${dest_sub}"
    docker run --rm --pull=never -u 0 \
      -e DST="/data/${dest_sub}" -e UID="${TARGET_UID}" -e GID="${TARGET_GID}" \
      -v "${VOLUME_NAME}":/data \
      -v "$(pwd)/${src_dir}":/mnt/src:ro \
      "${img}" sh -c '
        mkdir -p "$DST" && \
        cp -r /mnt/src/. "$DST"/ 2>/dev/null || true && \
        chown -R "$UID:$GID" "$DST"
      ' || echo "[WARN] Sync ${src_dir} -> ${dest_sub} fallita"
  else
    echo "[INFO] ${src_dir}/ non presente, salto sync."
  fi
}

preload_into_volume() {
  local root="$1"
  local excludes_str="$2"
  echo "[INFO] Pre-carica da $root (Optimized: single container)"
  [[ -d "$root" ]] || { echo "[INFO] $root non esiste, salto."; return; }

  # Run a single alpine container to handle all copies
  # We pass the excludes string as env var
  docker run --rm -u 0 \
    -e DST_ROOT="/data" -e UID="${TARGET_UID}" -e GID="${TARGET_GID}" \
    -e EXCLUDES="$excludes_str" \
    -v "${VOLUME_NAME}":/data \
    -v "$root":/mnt/src:ro \
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
    ' || echo "[WARN] Preload fallito"
}

# ========= Prompt backup offline =========
# Asks the user if they want to perform an offline backup
prompt_backup() {
  # Uso: prompt_backup <default:y|n>
  local def="${1:-n}" # default implicito: NO
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
      y|Y) log "Backup richiesto."; return 0 ;;
      n|N) log "Backup saltato.";   return 1 ;;
      *)   warn "Inserisci 'y' oppure 'n'." ;;
    esac
  done
}

# Performs the offline backup using restic-tools.sh
do_offline_backup() {
  log "Eseguo backup offline..."
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

# ========= Cloud Mutex (ensure only, NO set 1/keepalive) =========
derive_mutex_remote_dir() {
  if [[ -n "${MUTEX_REMOTE_DIR:-}" ]]; then
    echo "${MUTEX_REMOTE_DIR}"
    return
  fi
  local repo="${RESTIC_REPOSITORY#rclone:}"   # mega:/something
  local remote="${repo%%:*}"
  local sub="${CLOUD_MUTEX_DIR#/Root}"; sub="${sub#/}"
  echo "${remote}:/${sub}"
}

# Ensures the mutex exists on the cloud
cloud_mutex_prepare() {
  if [[ ! -x "${RCLONE_MUTEX_SH}" ]]; then
    warn "Mutex script non trovato o non eseguibile: ${RCLONE_MUTEX_SH}. Procedo senza ensure."
    return 0
  fi
  export MUTEX_REMOTE_DIR="$(derive_mutex_remote_dir)"
  export RCLONE_CONF_HOST
  export MUTEX_FILE
  log "Cloud mutex ensure su ${MUTEX_REMOTE_DIR}/${MUTEX_FILE} ..."
  "${RCLONE_MUTEX_SH}" ensure
}


# Releases the cloud mutex
cloud_mutex_release() {
  if [[ -n "${MUTEX_KEEPALIVE_PID:-}" ]]; then
    kill "${MUTEX_KEEPALIVE_PID}" 2>/dev/null || true
  fi
  if [[ -x "${RCLONE_MUTEX_SH}" ]]; then
    log "Rilascio cloud mutex (1→0)..."
    "${RCLONE_MUTEX_SH}" set 0 >/dev/null || true
  fi
}

# ========= Auto-OP Users =========
# Automatically grants OP status to users specified in the .env file
auto_op_users() {
  echo "DEBUG: Starting auto_op_users (waiting 120s for container creation...)"
  sleep 120s

  # Generate mods list
  log "Generating mods list to utils/mods_list.txt..."
  ls mods/ > ./utils/mods_list.txt 2>&1 || warn "Failed to list mods/"

  IFS=',' read -ra ADKINS <<< "${OPS:-}"
  echo "DEBUG: OPS='${OPS}', ADKINS='${ADKINS[@]}', count=${#ADKINS[@]}"
  for user in "${ADKINS[@]}"; do
    user=$(echo "$user" | xargs) # trim spaces
    [[ -z "$user" ]] && continue
    
    log "Auto-OP: Trying to assign operator to $user..."
    while true; do
      # Capture output and exit code
      if out=$(docker exec "${MC_CONTAINER_NAME}" rcon-cli op "$user" 2>&1); then
          # Exit code 0 -> RCON connected and command sent
          # Verify server response
          if [[ "$out" == *"Made"* || "$out" == *"Nothing changed"* ]]; then
            log "Auto-OP: Success! Server response: $out"
            break
          else
            # Strange case: exit 0 but unexpected output? Log and exit anyway (or retry?)
            # If server is online but responds something else, better log and exit to avoid infinite loop on logical errors.
            log "Auto-OP: Command sent but unexpected response: '$out'. Assuming success."
            break
          fi
      else
        # Exit code != 0 -> RCON failed (e.g. connection refused)
        log "Auto-OP: Failed op on $user. Output: '$out'. Retrying in 10s..."
        sleep 10
      fi
    done
  done
}

# ========= Avvio docker-compose =========
# Starts the Docker Compose services
compose_up() {
  local mode="${1:-auto}"  # auto | restoreon | restoreoff
  log "Starting Minecraft..."
  case "$mode" in
    restoreoff)
      log "Starting without restore from cloud storage..."
      # Use --exit-code-from mc so that if mc stops (AutoStop), backups container is also stopped.
      docker compose --env-file env/.env up --build --exit-code-from mc
      ;;
    restoreon|auto|*)
      log "Mode ${mode} -> using restore profile."
      # 1. Execute Restore (blocks until finish)
      # We target ONLY restore-backup service.
      docker compose -f docker-compose.yml -f ./images/minecraft-server/docker-compose.restore-overrides.yml \
        --profile restore --env-file env/.env up --build restore-backup

      # 2. Main Start
      # We do NOT include the restore-overrides (dependencies) nor the restore profile.
      # This avoids "container stopped" abort triggers from the completed restore service.
      log "Restore completed. Starting Server + Backups..."
      docker compose -f docker-compose.yml --env-file env/.env up --build --exit-code-from mc
      ;;
  esac
}

# ========= Main =========
# Main entry point
main() {
  load_env
  
  # --- Dynamic Dockerfile Selection ---
  # Version comparison logic
  version_ge() {
    local version_actual="$1"
    local version_required="$2"
    local lowest
    lowest="$(printf '%s\n%s' "$version_actual" "$version_required" | sort -V | head -n1)"
    [[ "$lowest" == "$version_required" ]]
  }

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

  ensure_volume
  log "Preflight permissions..."
  ensure_permissions
  preload_into_volume "$PRELOAD_ROOT" "$PRELOAD_EXCLUDES"
  # Clean up ephemeral alpine image immediately as requested
  docker rmi alpine:3.20 2>/dev/null || true

  # Mutex before any operation (avoids multi-host race)
  cloud_mutex_prepare

  # Offline backup BEFORE start
  # Updated rules:
  # - No args: NO prompt -> skip backup and start immediately
  # - Arg 'loadcurrbackup': forced backup without prompt
  # - Any other arg: prompt with default 'y'
  if [[ $# -eq 0 ]]; then
    log "No args -> skipping backup without prompt."
  elif [[ "${1:-}" == "loadcurrbackup" ]]; then
    log "Arg 'loadcurrbackup' -> performing backup without prompt."
    do_offline_backup
  else
    if prompt_backup "y"; then
      do_offline_backup
    else
      log "Starting without backup."
    fi
  fi

  # Avvio con/senza restore
  # Run auto-op in background redirecting log
  auto_op_users > ./utils/auto-op.log 2>&1 &
  compose_up "${1:-auto}"
  
  # Cleanup on exit
  log "Server stopped."
  # We do NOT run 'docker compose down' here anymore, so containers remain (Exited) for inspection.
  # Images are preserved for faster startup.
  # Alpine image was already removed after preload.
  
  log "Cleanup complete."
}

main "$@"
