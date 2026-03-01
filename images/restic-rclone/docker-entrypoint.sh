#!/bin/sh
set -eu

# ========== ENV base (Restic) ==========
: "${RESTIC_REPOSITORY:?RESTIC_REPOSITORY not set (e.g. rclone:mega:/modpack)}"
: "${RESTIC_PASSWORD:?RESTIC_PASSWORD not set}"
: "${RESTIC_HOSTNAME:=Mondo}"
: "${RESTIC_SNAPSHOT:=latest}"

# ========== ENV rclone/mutex ==========
: "${RCLONE_CONFIG:=/root/.config/rclone/rclone.conf}"  # mounted from compose
: "${MUTEX_FILE:=mutex.txt}"
: "${CLOUD_MUTEX_DIR:=/Root/modpack}"                   # used if MUTEX_REMOTE_DIR not provided
: "${MUTEX_REMOTE_DIR:=}"                               # e.g. mega:/tekkmodpackit (priority if set)
: "${CLOUD_MUTEX_EXPECT:=any}"                          # any|0|1 (see above)
: "${CLOUD_MUTEX_WAIT_SECS:=10}"                        # pause between polls

echo "[INFO] Restore entrypoint started"

# --------- Utils rclone ---------
rc() {
  rclone --config "$RCLONE_CONFIG" "$@"
}

derive_remote_dir() {
  if [ -n "$MUTEX_REMOTE_DIR" ]; then
    printf '%s' "$MUTEX_REMOTE_DIR"
    return
  fi
  # Derive remote (e.g. "mega") from RESTIC_REPOSITORY=rclone:<remote>:/repo
  repo="${RESTIC_REPOSITORY#rclone:}"   # mega:/qualcosa
  remote="${repo%%:*}"                  # mega
  sub="${CLOUD_MUTEX_DIR#/Root}"        # /modpack -> modpack
  sub="${sub#/}"
  printf '%s' "${remote}:/${sub}"
}

REMOTE_DIR="$(derive_remote_dir)"
REMOTE_FILE="${REMOTE_DIR%/}/${MUTEX_FILE}"

ensure_mutex_file() {
  # create folder and mutex=0 if missing (temp upload + atomic rename)
  rc mkdir "$REMOTE_DIR" >/dev/null 2>&1 || true
  if ! rc ls "$REMOTE_FILE" >/dev/null 2>&1; then
    tmp_local="$(mktemp)"; printf '0\n' > "$tmp_local"
    tmp_remote="${REMOTE_DIR%/}/.${MUTEX_FILE}.tmp.$$"
    rc copyto "$tmp_local" "$tmp_remote" >/dev/null
    rc moveto "$tmp_remote" "$REMOTE_FILE" >/dev/null
    rm -f "$tmp_local"
  fi
}

read_mutex() {
  if ! out="$(rc cat "$REMOTE_FILE" 2>/dev/null || true)"; then
    echo 0; return
  fi
  val="$(printf '%s' "$out" | dd bs=1 count=1 2>/dev/null | tr -dc '01' || true)"
  [ "$val" = "1" ] && echo 1 || echo 0
}

# Atomic write: temporary upload + rename (avoids equal size issues)
write_mutex_value() {
  v="$1"  # "0" o "1"
  tmp_local="$(mktemp)"; printf '%s\n' "$v" > "$tmp_local"

  # Robust overwrite on MEGA:
  rc deletefile "$REMOTE_FILE" >/dev/null 2>&1 || true
  rc copyto --ignore-times "$tmp_local" "$REMOTE_FILE" >/dev/null

  rm -f "$tmp_local"

  # Actual verification
  back="$(rc cat "$REMOTE_FILE" 2>/dev/null | dd bs=1 count=1 2>/dev/null | tr -dc '01' || true)"
  if [ "$back" != "$v" ]; then
    echo "[ERROR] Mutex write failed: wrote '$v', read '$back' on $REMOTE_FILE"
    return 1
  fi
}

# CAS 0->1: try to acquire; if already 1, wait/retry
cas_acquire_mutex() {
  ensure_mutex_file
  tries="${CLOUD_MUTEX_TRIES:-30}"
  wait_s="${CLOUD_MUTEX_WAIT_SECS:-10}"
  i=1
  while [ "$i" -le "$tries" ]; do
    cur="$(read_mutex)"
    if [ "$cur" = "0" ]; then
      if write_mutex_value "1"; then
        echo "[INFO] Mutex acquired (0→1)."
        return 0
      else
        echo "[WARN] Acquisition attempt failed; retrying in ${wait_s}s (attempt $i/$tries)..."
      fi
    else
      echo "[INFO] Mutex=$cur; waiting ${wait_s}s (attempt $i/$tries) to become 0 to acquire..."
    fi
    sleep "$wait_s"
    i=$((i+1))
  done
  echo "[ERROR] Impossible to acquire mutex (still !=1 after $tries attempts)."
  exit 3
}

wait_for_mutex() {
  case "$CLOUD_MUTEX_EXPECT" in
    any) return 0 ;;
    0|1)
      ensure_mutex_file
      cur="$(read_mutex)"
      while [ "$cur" != "$CLOUD_MUTEX_EXPECT" ]; do
        echo "[INFO] Mutex=$cur; waiting ${CLOUD_MUTEX_WAIT_SECS}s until it becomes ${CLOUD_MUTEX_EXPECT} (${REMOTE_FILE})"
        sleep "$CLOUD_MUTEX_WAIT_SECS"
        cur="$(read_mutex)"
      done
      ;;
    *)
      echo "[WARN] Invalid CLOUD_MUTEX_EXPECT: $CLOUD_MUTEX_EXPECT (using 'any')"
      ;;
  esac
}

# --------- Lock Restic ---------
restic_lock_count() {
  restic -r "$RESTIC_REPOSITORY" list locks 2>/dev/null | wc -l | tr -d ' '
}

wait_resty_locks_clear() {
  echo "[INFO] Checking Restic locks on the repo..."
  locks="$(restic_lock_count || echo 0)"
  while [ "${locks:-0}" -gt 0 ]; do
    echo "[INFO] Waiting 10s: active Restic locks = ${locks}"
    sleep 10
    locks="$(restic_lock_count || echo 0)"
  done
}

# --------- Restore ---------
do_restore() {
  echo "[INFO] Restoring snapshot '${RESTIC_SNAPSHOT}' from repo ($RESTIC_REPOSITORY, host=$RESTIC_HOSTNAME)"
  
  if restic -r "$RESTIC_REPOSITORY" restore "$RESTIC_SNAPSHOT" \
    --target / \
    --host "$RESTIC_HOSTNAME" \
    --no-lock; then
      echo "[OK] Restore completed."
  else
      RET=$?
      echo "[WARN] Restore command exited with code $RET. Checking if this is a fresh install (no snapshots)..."
      
      # Check if any snapshot exists for this host to distinguish between "empty repo" and "restore error"
      # We capture the output. If 'restic snapshots' itself fails (e.g. connectivity), we abort.
      if ! snaps=$(restic -r "$RESTIC_REPOSITORY" snapshots --host "$RESTIC_HOSTNAME" 2>&1); then
          echo "[ERROR] Unable to list snapshots to verify empty state. Error: $snaps"
          exit $RET
      fi
      
      # Look for a snapshot ID (8 hex chars at start of line)
      if echo "$snaps" | grep -qE "^[0-9a-f]{8}"; then
          echo "[ERROR] Snapshots found, but restore failed. Inspect logs above."
          exit $RET
      else
           echo "[INFO] No snapshot found for host '$RESTIC_HOSTNAME' (or filter unmatched). Assuming clean installation/fresh start."
           return 0
      fi
  fi
}

# --------- Main ---------
main() {
  echo "[INFO] Remote mutex: ${REMOTE_FILE}"
  # Now not "wait_for_mutex 0", but trying to acquire ourselves:
  cas_acquire_mutex

  wait_resty_locks_clear
  do_restore

  # Do not release the mutex: the MC server will keep the lock during the run and release it at stop
}


main "$@"
