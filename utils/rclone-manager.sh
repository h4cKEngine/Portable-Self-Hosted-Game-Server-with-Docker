#!/bin/bash

set -euo pipefail

# ==============================================================================
# CONFIGURATION
# ==============================================================================
ENV_DIR="env"
CONF="${ENV_DIR}/rclone.conf"
RESTIC_IMAGE_DEFAULT="docker.io/tofran/restic-rclone:0.17.0_1.68.2"

# Global variable: if 1, force container usage
USE_CONTAINER_MODE=0

# ==============================================================================
# UTILITIES
# ==============================================================================
msg()  { printf "[INFO] %s\n" "$*"; }
warn() { printf "[WARN] %s\n" "$*" >&2; }
err()  { printf "[ERRORE] %s\n" "$*" >&2; exit 1; }

# Loads image from .env or uses default
load_restic_image() {
  local img
  img="$(grep -E '^[[:space:]]*RESTIC_IMAGE=' env/.env 2>/dev/null | tail -n1 | cut -d= -f2-)"
  echo "${img:-$RESTIC_IMAGE_DEFAULT}"
}

# Intelligent wrapper to execute rclone
# Automatically decides whether to use HOST or CONTAINER
run_rclone() {
  # If in container mode, or if host rclone is missing, use docker
  if [[ "$USE_CONTAINER_MODE" -eq 1 ]] || ! command -v rclone >/dev/null 2>&1; then
    local img; img="$(load_restic_image)"
    # Execute via docker
    docker run --rm \
      -v "$PWD/${CONF}":/root/.config/rclone/rclone.conf:ro \
      "$img" rclone "$@"
  else
    # Execute via host
    rclone --config "$CONF" "$@"
  fi
}

# Checks if host rclone supports mega backend
host_has_mega_support() {
  command -v rclone >/dev/null 2>&1 && rclone help backends 2>/dev/null | grep -qi '^ *mega'
}

# Converts file to unix format if dos2unix is available
maybe_dos2unix() {
  command -v dos2unix >/dev/null 2>&1 && dos2unix -q "$CONF" || true
}

# Sanitizes a string by removing spaces and strange characters
sanitize_str() {
  # Removes spaces and strange characters
  printf '%s' "$1" | sed 's/ /_/g' | LC_ALL=C tr -cd '[:alnum:]_.-'
}

# ==============================================================================
# CORE FUNCTIONS
# ==============================================================================
# Ensures the setup directory and config file exist
ensure_setup() {
  mkdir -p "$ENV_DIR"
  [[ -f "$CONF" ]] || : > "$CONF"
  chmod 600 "$CONF" 2>/dev/null || true
}

# Creates a backup of the configuration file
backup_conf() {
  local ts; ts="$(date +%Y%m%d-%H%M%S)"
  # Simple backup: copy file
  cp -a "$CONF" "${CONF}.bak.${ts}"
  msg "Backup created: ${CONF}.bak.${ts}"
}

# Ensures that rclone is ready to be used (checks requirements and host support)
ensure_rclone_ready() {
  # 1. Try requirements.sh (idempotent)
  chmod +x ./utils/requirements.sh 2>/dev/null || true
  msg "Checking requirements..."
  ./utils/requirements.sh || warn "requirements.sh reported error/warning."

  # 2. Final check
  hash -r
  if host_has_mega_support; then
    msg "Rclone host OK (with mega support)."
    USE_CONTAINER_MODE=0
    return 0
  fi

  # 3. Fallback
  warn "Host rclone not available or without mega. Switching to CONTAINER mode."
  if ! command -v docker >/dev/null 2>&1; then
     err "Neither rclone nor docker found. Cannot proceed."
  fi
  USE_CONTAINER_MODE=1
}

# Updates or inserts a remote block in the configuration file
upsert_remote_block() {
  local remote="$1"
  local block_file="$2"
  local tmp; tmp="$(mktemp)"

  # AWK logic: copy everything EXCEPT the specified remote block
  awk -v remote="$remote" '
    BEGIN { skip=0 }
    {
      if (skip) { if ($0 ~ /^\[.+\]/) { skip=0; print $0 }; next }
      if ($0 ~ "^\\[" remote "\\][[:space:]]*$") { skip=1; next }
      print $0
    }
  ' "$CONF" > "$tmp"

  # Add newline if missing, then append new block
  [[ -s "$tmp" && -n "$(tail -c1 "$tmp" 2>/dev/null)" ]] && echo "" >> "$tmp"
  cat "$block_file" >> "$tmp"
  
  mv "$tmp" "$CONF"
  rm -f "$block_file"
}

# ==============================================================================
# MAIN
# ==============================================================================
# Main entry point for Rclone Manager
main() {
  echo "=== Rclone Manager ==="
  ensure_setup
  ensure_rclone_ready

  echo "--- Remote Configuration ---"
  read -r -p "Service (e.g. mega): " SERVICE
  SERVICE="${SERVICE:-mega}"
  SERVICE_CLEAN="$(sanitize_str "$SERVICE" | tr '[:upper:]' '[:lower:]')"
  
  [ -z "$SERVICE_CLEAN" ] && err "Invalid service name"

  REMOTE_NAME="$SERVICE_CLEAN"

  read -r -p "Email/Username: " USERNAME
  [ -z "$USERNAME" ] && err "Username required"

  read -r -s -p "Password: " PASSWORD
  echo ""
  [ -z "$PASSWORD" ] && err "Password required"

  msg "Obscuring password..."
  # We use our wrapper function here! Magic!
  # Note: obscure wants 'rclone obscure', run_rclone already adds 'rclone' if using docker?
  # No, run_rclone executes 'docker ... rclone $@'. So we must pass 'obscure'.
  # If mode=host, it executes 'rclone --config ... obscure'.
  # --config does not bother obscure.
  OBSCURED_PASS="$(run_rclone obscure -- "$PASSWORD" | tail -n1)"
  
  if [ -z "$OBSCURED_PASS" ]; then
    err "Failed to obtain obscured password."
  fi

  # Configuration block creation
  local tmpblock; tmpblock="$(mktemp)"
  cat > "$tmpblock" <<EOF
[${REMOTE_NAME}]
type = ${SERVICE_CLEAN}
user = ${USERNAME}
pass = ${OBSCURED_PASS}
EOF

  msg "Updating ${CONF}..."
  backup_conf
  upsert_remote_block "$REMOTE_NAME" "$tmpblock"
  
  maybe_dos2unix
  chmod 600 "$CONF"
  msg "Done. Configured [${REMOTE_NAME}]."

  # Test
  read -r -p "Do you want to test the connection (lsd)? [Y/n]: " REPLY
  if [[ "${REPLY:-Y}" =~ ^[Yy]$ ]]; then
    msg "Directory list test..."
    run_rclone lsd "${REMOTE_NAME}:" || warn "Test failed."
  fi
}

main "$@"
