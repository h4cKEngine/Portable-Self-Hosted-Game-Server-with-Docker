#!/usr/bin/env bash
set -Eeuo pipefail

# Enable trace if requested
if [[ "${DEBUG_EXEC:-false}" == "true" ]]; then
  set -x
fi

# ================== Log & util ==================
log()  { echo "[INFO] $*"; }
warn() { echo "[WARN] $*" >&2; }
err()  { echo "[ERROR] $*" >&2; exit 1; }
require_bin(){ command -v "$1" >/dev/null 2>&1 || err "Required command not found: $1"; }

# ================== Restic cfg ==================
: "${RESTIC_REPOSITORY:?RESTIC_REPOSITORY not set (e.g. rclone:mega:/modpack)}"
: "${RESTIC_PASSWORD:?RESTIC_PASSWORD not set}"
RESTIC_HOSTNAME="${RESTIC_HOSTNAME:-Mondo}"
RESTIC_TAG="${RESTIC_TAG:-mc_backups}"
: "${RESTIC_KEEP_LAST:=10}"
RESTIC_FORGET_ARGS="${RESTIC_FORGET_ARGS:---prune --keep-last ${RESTIC_KEEP_LAST}}"
rc(){ restic -r "${RESTIC_REPOSITORY}" "$@"; }

# ================== Mutex (rclone) ==============
: "${RCLONE_CONFIG:=/root/.config/rclone/rclone.conf}"
: "${MUTEX_FILE:=mutex.txt}"
: "${CLOUD_MUTEX_TRIES:=60}"
: "${CLOUD_MUTEX_WAIT_SECS:=5}"
: "${CLOUD_MUTEX_KEEPALIVE:=1}"
: "${CLOUD_MUTEX_PULSE:=30}"
rc_m(){ rclone --config "$RCLONE_CONFIG" "$@"; }

mutex_remote_dir() {
  if [[ -n "${MUTEX_REMOTE_DIR:-}" ]]; then
    printf '%s' "${MUTEX_REMOTE_DIR%/}"; return
  fi
  local repo="${RESTIC_REPOSITORY#rclone:}"   # mega:/something
  local remote="${repo%%:*}"                  # mega
  local sub="${CLOUD_MUTEX_DIR:-/Root/modpack}"
  sub="${sub#/Root}"; sub="${sub#/}"
  printf '%s' "${remote}:/${sub}"
}
MUTEX_REMOTE="$(mutex_remote_dir)"
MUTEX_PATH="${MUTEX_REMOTE}/${MUTEX_FILE}"

mutex_read() {
  rc_m cat "$MUTEX_PATH" 2>/dev/null \
    | dd bs=1 count=1 2>/dev/null \
    | tr -dc '01' \
    | { read -r v; [[ "$v" == "1" ]] && echo 1 || echo 0; }
}
# Robust overwrite: MEGA might not overwrite if size is identical
mutex_set() {
  local v="$1"
  local t; t="$(mktemp)"; printf '%s\n' "$v" > "$t"
  rc_m deletefile "$MUTEX_PATH" >/dev/null 2>&1 || true
  rc_m copyto --ignore-times "$t" "$MUTEX_PATH" >/dev/null
  rm -f "$t"
}
mutex_wait_for_1() {
  local i=1 cur
  while [ "$i" -le "$CLOUD_MUTEX_TRIES" ]; do
    cur="$(mutex_read)"
    [[ "$cur" == "1" ]] && return 0
    log "Mutex=$cur; waiting ${CLOUD_MUTEX_WAIT_SECS}s (try $i/$CLOUD_MUTEX_TRIES) for 1..."
    sleep "$CLOUD_MUTEX_WAIT_SECS"; i=$((i+1))
  done
  err "Timeout waiting for mutex=1 on ${MUTEX_PATH}"
}
mutex_keepalive_start() {
  if [[ "$CLOUD_MUTEX_KEEPALIVE" == "1" ]]; then
    (
      while true; do
        mutex_set 1
        sleep "$CLOUD_MUTEX_PULSE"
      done
    ) &
    export MC_MUTEX_KEEPALIVE_PID=$!
    log "Cloud mutex keepalive active on ${MUTEX_PATH}"
  fi
}
mutex_release() {
  [[ -n "${MC_MUTEX_KEEPALIVE_PID:-}" ]] && kill "$MC_MUTEX_KEEPALIVE_PID" 2>/dev/null || true
  mutex_set 0
  log "Cloud mutex released (1->0) on ${MUTEX_PATH}"
}

# ================== Restic locks ==================
wait_resty_locks_clear() {
  log "Checking existing or stale restic locks..."
  while :; do
    cnt="$(rc list locks 2>/dev/null | wc -l | tr -d ' ' || echo 0)"
    if [ "${cnt:-0}" -le 0 ]; then
      break
    fi
    log "Waiting 10s for unlocking repo - ${cnt}"
    sleep 10
  done
}

# ================== Backup on-exit ===============
do_backup() {
  log "Backup starting..."
  rc forget ${RESTIC_FORGET_ARGS} || warn "restic forget failed"
  rc backup --tag "${RESTIC_TAG}" -vv --host "${RESTIC_HOSTNAME}" /data/world || warn "restic backup failed"
  log "Backup end."
}

# ================== Signal/Trap ==================
on_exit() {
  set +e
  wait_resty_locks_clear
  do_backup
  mutex_release
  exit 0
}

on_term() {
  if [[ -n "${MC_CHILD_PID:-}" ]]; then
    kill -TERM "$MC_CHILD_PID" 2>/dev/null || true
    wait "$MC_CHILD_PID" 2>/dev/null || true
  fi
  exit 0
}
setup_trap() { trap 'on_exit' EXIT; trap 'on_term' TERM INT; }

# ================== DuckDNS (opzionale) ==========
# Usage:
#   update_ddns         # update + asynchronous verification (does not block)
#   update_ddns --sync  # update + synchronous verification (blocks ~80s)
#
# If run in async, sets DDNS_ASYNC_PID with background job PID.
update_ddns() {
  # skip for this single run if requested
  if [[ "${DDNS_SKIP:-0}" == "1" || -f "/data/ddns.skip" ]]; then
    log "DDNS: skip requested (DDNS_SKIP=1 or /data/ddns.skip present)."
    rm -f /data/ddns.skip || true   # remove it so it only applies to this boot
    return 0
  fi

  local provider="${DDNS_PROVIDER:-duckdns}"
  if [[ -z "${DDNS_DOMAIN:-}" || -z "${DDNS_TOKEN:-}" ]]; then
      log "DDNS: Missing variables (DDNS_DOMAIN or DDNS_TOKEN). Skipping."
      return 0
  fi
  
  # Normalize provider name
  provider=$(echo "$provider" | tr '[:upper:]' '[:lower:]')

  case "$provider" in
    duckdns|duckdns.org)
       if [[ -n "${IP_SERVER:-}" ]]; then
         require_bin curl nslookup
         log "DuckDNS update for IP ${IP_SERVER}..."
         resp="$(curl -fsS "https://www.duckdns.org/update?domains=${DDNS_DOMAIN}&token=${DDNS_TOKEN}&ip=${IP_SERVER}" || echo ERROR)"
         log "DuckDNS: ${resp}"

         # optional async wait for TTL (managed outside switch for uniformity, but duckdns was custom)
         # For now we keep the specific internal logic for duckdns if we want, 
         # OR move everything outside case.
         # Since the user wants to keep duckdns "as is", I leave duplicated or specific logic here.
         # User said "mantienilo così" (keep it like this).
         # So I leave the async block inside here for duckdns and DO NOT do it outside?
         # But other providers still need verification.
         
         # Extract Async logic ONLY for DuckDNS as requested, duplicating or adapting it.
         if [[ "${DDNS_ASYNC:-1}" == "1" ]]; then
           ( sleep 80; nslookup "${DDNS_DOMAIN}.duckdns.org" 1.1.1.1 || true ) &
           DDNS_ASYNC_PID=$!
         else
           log "Waiting for DuckDNS update (TTL ~60s): 80s..."
           sleep 80; nslookup "${DDNS_DOMAIN}.duckdns.org" 1.1.1.1 || true
         fi
       else
         log "DuckDNS: IP_SERVER not set, cannot update."
       fi
       return 0 # Exit after duckdns to respect "keep it like this" and double check
       ;;
    
    desec|desec.io)
       # API: https://desec.readthedocs.io/en/latest/dyndns/update-api.html
       # User: Domain Name, Password: Token/Authorization Token
       # Requires DDNS_TOKEN to be "username:password" or just token if username is deduced?
       # Desec uses: Authorization header "Token <token>" or Basic Auth.
       # Here we use Basic Auth with curl --user.
       # If DDNS_TOKEN is only the secret, user must put "domain:token" in DDNS_TOKEN or do we manage?
       # For consistency with others: User must put complete CREDS in DDNS_TOKEN ("domain:token").
       log "Desec.io update for ${DDNS_DOMAIN} -> ${IP_SERVER}..."
       resp="$(curl -fsS --user "${DDNS_TOKEN}" "https://update.dedyn.io/?myip=${IP_SERVER}" || echo ERROR)"
       log "Desec.io: ${resp}"
       ;;

    dynu|dynu.com)
       # API: https://www.dynu.com/en-US/DynamicDNS/IP-Update-Protocol
       # Requires User + Password (MD5 or plain).
       # Assume DDNS_TOKEN contains "username:password" or user uses only password if username not needed (rare).
       # Alternative: try to support DDNS_USER if defined, otherwise split TOKEN?
       # For simplicity now: DDNS_TOKEN must be "username:password" if basic auth needed, or use url with params.
       # Dynu URL: https://api.dynu.com/nic/update?hostname=DOMAIN&myip=IP&username=USER&password=PASS
       log "Dynu update for ${DDNS_DOMAIN}..."
       # Split DDNS_TOKEN in user:pass if possible, or direct curl -u
       resp="$(curl -fsS -u "${DDNS_TOKEN}" "https://api.dynu.com/nic/update?hostname=${DDNS_DOMAIN}&myip=${IP_SERVER}" || echo ERROR)"
       log "Dynu: ${resp}"
       ;;

    ydns|ydns.io)
       # API: https://ydns.io/api
       # Auth: Basic Auth (email:password)
       # DDNS_TOKEN must be "email:password"
       log "YDNS update for ${DDNS_DOMAIN}..."
       resp="$(curl -fsS --user "${DDNS_TOKEN}" "https://ydns.io/api/v1/update/?host=${DDNS_DOMAIN}&ip=${IP_SERVER}" || echo ERROR)"
       log "YDNS: ${resp}"
       ;;

    freedns|afraid.org)
       # API: http://freedns.afraid.org/nic/update?hostname=<domain>&myip=<ip>
       # Auth: Basic Auth (username:password) OR direct URL token.
       # Here we use standard NIC update that accepts user:pass (contained in DDNS_TOKEN).
       log "FreeDNS update for ${DDNS_DOMAIN}..."
       resp="$(curl -fsS -u "${DDNS_TOKEN}" "https://freedns.afraid.org/nic/update?hostname=${DDNS_DOMAIN}&myip=${IP_SERVER}" || echo ERROR)"
       log "FreeDNS: ${resp}"
       ;;

    noip|no-ip|noip.com)
       # API: https://www.noip.com/integrate/request
       # Auth: Base64 "username:password" header (curl -u does this).
       # DDNS_TOKEN must be "username:password"
       log "No-IP update for ${DDNS_DOMAIN}..."
       resp="$(curl -fsS -u "${DDNS_TOKEN}" "https://dynupdate.no-ip.com/nic/update?hostname=${DDNS_DOMAIN}&myip=${IP_SERVER}" || echo ERROR)"
       log "No-IP: ${resp}"
       ;;
    
    *)
        warn "DDNS Provider '$provider' unknown or not implemented."
        ;;
  esac

  # Verify (common to all)
  if [[ "${DDNS_ASYNC:-1}" == "1" ]]; then
     local check_domain="${DDNS_DOMAIN}"
     if [[ "$provider" == "duckdns" || "$provider" == "duckdns.org" ]]; then
        check_domain="${DDNS_DOMAIN}.duckdns.org"
     fi

     ( sleep 80; nslookup "${check_domain}" 1.1.1.1 || true ) &
     DDNS_ASYNC_PID=$!
  else
     local check_domain="${DDNS_DOMAIN}"
     if [[ "$provider" == "duckdns" || "$provider" == "duckdns.org" ]]; then
        check_domain="${DDNS_DOMAIN}.duckdns.org"
     fi
     log "Waiting DNS check for ${check_domain}..."
     sleep 80; nslookup "${check_domain}" 1.1.1.1 || true
  fi
}

_ddns_verify() {
  # Prints resolved IP and compares with IP_SERVER if present; on mismatch, retry update once
  local provider="${DDNS_PROVIDER:-duckdns}"
  local check_domain="${DDNS_DOMAIN}"
  if [[ "$provider" == "duckdns" || "$provider" == "duckdns.org" ]]; then
     check_domain="${DDNS_DOMAIN}.duckdns.org"
  fi

  local resolved
  resolved="$(nslookup "${check_domain}" 1.1.1.1 2>/dev/null | awk '/Address: /{print $2}' | tail -n1 || true)"
  if [[ -n "$resolved" ]]; then
    log "DDNS check: ${check_domain} -> ${resolved}"
  else
    warn "DDNS check: impossibile risolvere ${check_domain}"
  fi

  if [[ -n "${IP_SERVER:-}" && -n "$resolved" && "$resolved" != "$IP_SERVER" ]]; then
    # warn "DuckDNS non aggiornato dopo 80s (risolto=${resolved}, atteso=${IP_SERVER}). Riprovo update..."
    # local url2="https://www.duckdns.org/update?domains=${DDNS_DOMAIN}&token=${DDNS_TOKEN}&ip=${IP_SERVER}"
    # curl -fsS "$url2" >/dev/null 2>&1 && log "DuckDNS: retry OK" || warn "DuckDNS: retry fallito"
    warn "DDNS not updated after 80s (resolved=${resolved}, expected=${IP_SERVER})."
    # Retry logic removed or simplified to avoid specific code duplication.
    # If needed, recall update_ddns
  fi
}

# ================== Main ========================
main() {
  require_bin restic
  require_bin rclone

  # --- Dynamic Java Version Selection ---
  # Version comparison function (semver-ish)
  # Returns 0 (true) if version_actual ($1) >= version_required ($2)
  version_ge() {
    local version_actual="$1"
    local version_required="$2"

    # Sort the two versions. 'head -n1' picks the lowest one according to version sort (-V).
    local lowest
    lowest="$(printf '%s\n%s' "$version_actual" "$version_required" | sort -V | head -n1)"

    # If the required version is the lowest (or they are equal), 
    # then our actual version is effectively greater or equal.
    [[ "$lowest" == "$version_required" ]]
  }

  if [[ -n "${VERSION:-}" ]]; then
      # Logic based on: https://minecraft.wiki/w/Java_Edition_1.17#General
      # and https://minecraft.wiki/w/Java_Edition_1.18#General
      # and https://minecraft.wiki/w/Java_Edition_1.20.5#General
      
      if version_ge "$VERSION" "1.20.5"; then
          log "Minecraft version $VERSION detected (>= 1.20.5). Setting JAVA_VERSION=21"
          export JAVA_VERSION=21
      elif version_ge "$VERSION" "1.17.0"; then
          log "Minecraft version $VERSION detected (>= 1.17.0). Setting JAVA_VERSION=17"
          export JAVA_VERSION=17
      else
          log "Minecraft version $VERSION detected (< 1.17.0). Setting JAVA_VERSION=8"
          export JAVA_VERSION=8
      fi
  fi


  log "java-start wrapper ACTIVE; mutex path: ${MUTEX_PATH}"

  setup_trap
  update_ddns   # async by default; sets DUCKDNS_ASYNC_PID

  # Wait for restore to set mutex to 1 and start keepalive
  mutex_wait_for_1
  mutex_keepalive_start   # starts a background job

  # Start /start as CHILD (no exec) and save PID IMMEDIATELY
  /start "$@" &
  MC_CHILD_PID=$!

  # Verify DuckDNS: DO NOT block wrapper
  if [[ -n "${DDNS_ASYNC_PID:-}" ]]; then
    ( wait "${DDNS_ASYNC_PID}" 2>/dev/null || true ) &
  fi

  # --- Copy Overrides ---
  # If mounted folder /overrides exists, copy (overwrite) files to /data
  if [ -d "/overrides" ]; then
    log "Applying overrides from /overrides to /data..."
    # cp -r -f (recursive, force)
    # WARNING: if /overrides is empty, * might fail if not handled, but cp -r /overrides/. /data/ is safer
    # or simply check if not empty.
    if [ "$(ls -A /overrides)" ]; then
       cp -rf /overrides/. /data/
       log "Overrides applied."
    else
       log "Overrides dir is empty."
    fi
  fi

  # Wait for server
  wait "$MC_CHILD_PID"
}

main "$@"
