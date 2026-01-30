#!/bin/sh
set -eu

# ========== ENV base (Restic) ==========
: "${RESTIC_REPOSITORY:?RESTIC_REPOSITORY non impostato (es: rclone:mega:/modpack)}"
: "${RESTIC_PASSWORD:?RESTIC_PASSWORD non impostato}"
: "${RESTIC_HOSTNAME:=Mondo}"
: "${RESTIC_SNAPSHOT:=latest}"

# ========== ENV rclone/mutex ==========
: "${RCLONE_CONFIG:=/root/.config/rclone/rclone.conf}"  # montato dal compose
: "${MUTEX_FILE:=mutex.txt}"
: "${CLOUD_MUTEX_DIR:=/Root/modpack}"                   # usato se non fornisci MUTEX_REMOTE_DIR
: "${MUTEX_REMOTE_DIR:=}"                               # es. mega:/tekkmodpackit (prioritario se settato)
: "${CLOUD_MUTEX_EXPECT:=any}"                          # any|0|1 (vedi sopra)
: "${CLOUD_MUTEX_WAIT_SECS:=10}"                        # pausa tra i poll

echo "[INFO] Entrypoint restore avviato"

# --------- Utils rclone ---------
rc() {
  rclone --config "$RCLONE_CONFIG" "$@"
}

derive_remote_dir() {
  if [ -n "$MUTEX_REMOTE_DIR" ]; then
    printf '%s' "$MUTEX_REMOTE_DIR"
    return
  fi
  # Deriva remote (es. "mega") da RESTIC_REPOSITORY=rclone:<remote>:/repo
  repo="${RESTIC_REPOSITORY#rclone:}"   # mega:/qualcosa
  remote="${repo%%:*}"                  # mega
  sub="${CLOUD_MUTEX_DIR#/Root}"        # /modpack -> modpack
  sub="${sub#/}"
  printf '%s' "${remote}:/${sub}"
}

REMOTE_DIR="$(derive_remote_dir)"
REMOTE_FILE="${REMOTE_DIR%/}/${MUTEX_FILE}"

ensure_mutex_file() {
  # crea cartella e mutex=0 se mancanti (upload temp + rename atomico)
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

# Scrittura atomica: upload temporaneo + rename (evita problemi di size uguale)
write_mutex_value() {
  v="$1"  # "0" oppure "1"
  tmp_local="$(mktemp)"; printf '%s\n' "$v" > "$tmp_local"

  # Overwrite robusto su MEGA:
  rc deletefile "$REMOTE_FILE" >/dev/null 2>&1 || true
  rc copyto --ignore-times "$tmp_local" "$REMOTE_FILE" >/dev/null

  rm -f "$tmp_local"

  # Verifica effettiva
  back="$(rc cat "$REMOTE_FILE" 2>/dev/null | dd bs=1 count=1 2>/dev/null | tr -dc '01' || true)"
  if [ "$back" != "$v" ]; then
    echo "[ERROR] Scrittura mutex fallita: scritto '$v', letto '$back' su $REMOTE_FILE"
    return 1
  fi
}

# CAS 0->1: prova ad acquisire; se già 1, attende/retry
cas_acquire_mutex() {
  ensure_mutex_file
  tries="${CLOUD_MUTEX_TRIES:-30}"
  wait_s="${CLOUD_MUTEX_WAIT_SECS:-10}"
  i=1
  while [ "$i" -le "$tries" ]; do
    cur="$(read_mutex)"
    if [ "$cur" = "0" ]; then
      if write_mutex_value "1"; then
        echo "[INFO] Mutex acquisito (0→1)."
        return 0
      else
        echo "[WARN] Tentativo di acquisizione fallito; ritento tra ${wait_s}s (tentativo $i/$tries)..."
      fi
    else
      echo "[INFO] Mutex=$cur; attendo ${wait_s}s (tentativo $i/$tries) che diventi 0 per acquisire..."
    fi
    sleep "$wait_s"
    i=$((i+1))
  done
  echo "[ERROR] Impossibile acquisire mutex (ancora !=1 dopo $tries tentativi)."
  exit 3
}

wait_for_mutex() {
  case "$CLOUD_MUTEX_EXPECT" in
    any) return 0 ;;
    0|1)
      ensure_mutex_file
      cur="$(read_mutex)"
      while [ "$cur" != "$CLOUD_MUTEX_EXPECT" ]; do
        echo "[INFO] Mutex=$cur; attendo ${CLOUD_MUTEX_WAIT_SECS}s finché diventa ${CLOUD_MUTEX_EXPECT} (${REMOTE_FILE})"
        sleep "$CLOUD_MUTEX_WAIT_SECS"
        cur="$(read_mutex)"
      done
      ;;
    *)
      echo "[WARN] CLOUD_MUTEX_EXPECT invalido: $CLOUD_MUTEX_EXPECT (uso 'any')"
      ;;
  esac
}

# --------- Lock Restic ---------
restic_lock_count() {
  restic -r "$RESTIC_REPOSITORY" list locks 2>/dev/null | wc -l | tr -d ' '
}

wait_resty_locks_clear() {
  echo "[INFO] Controllo lock Restic sul repo..."
  locks="$(restic_lock_count || echo 0)"
  while [ "${locks:-0}" -gt 0 ]; do
    echo "[INFO] Attendo 10s: lock Restic attivi = ${locks}"
    sleep 10
    locks="$(restic_lock_count || echo 0)"
  done
}

# --------- Restore ---------
do_restore() {
  echo "[INFO] Ripristino snapshot '${RESTIC_SNAPSHOT}' dal repo ($RESTIC_REPOSITORY, host=$RESTIC_HOSTNAME)"
  
  if restic -r "$RESTIC_REPOSITORY" restore "$RESTIC_SNAPSHOT" \
    --target / \
    --host "$RESTIC_HOSTNAME" \
    --no-lock; then
      echo "[OK] Restore completato."
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
           echo "[INFO] Nessuno snapshot trovato per host '$RESTIC_HOSTNAME' (o filtro non matchato). Assumo installazione pulita/fresh start."
           return 0
      fi
  fi
}

# --------- Main ---------
main() {
  echo "[INFO] Mutex remoto: ${REMOTE_FILE}"
  # Ora non “wait_for_mutex 0”, ma prova ad acquisire noi:
  cas_acquire_mutex

  wait_resty_locks_clear
  do_restore

  # Non rilascia il mutex: il server MC terrà il lock durante il run e lo rilascerà allo stop
}


main "$@"
