#!/bin/bash

set -Eeuo pipefail

echo "[INFO] Requirements for rclone (mega backend) and unzip"

# Use sudo if available
SUDO=""
if command -v sudo >/dev/null 2>&1; then
  SUDO="sudo"
fi

if [[ "${1:-}" == "uninstall" ]]; then
  echo "[INFO] UNINSTALL MODE: Removing rclone, unzip, curl..."
  $SUDO apt-get remove -y rclone unzip curl || true
  # Also removes manual binary if it exists in /usr/bin or /usr/local/bin
  $SUDO rm -f /usr/bin/rclone /usr/local/bin/rclone || true
  echo "[DONE] Packages removed."
  exit 0
fi

# Preventive check: if rclone is already installed and supports mega, exit
if command -v rclone >/dev/null 2>&1; then
  if rclone help backends 2>/dev/null | grep -qi '^\s*mega\b'; then
    echo "[OK] Rclone is already installed and supports 'mega'. No action needed."
    exit 0
  fi
fi


# Use sudo if available
SUDO=""
if command -v sudo >/dev/null 2>&1; then
  SUDO="sudo"
fi

echo "[INFO] Updating apt and installing unzip, curl, ca-certificates..."
$SUDO apt-get update -y
$SUDO apt-get install -y unzip curl ca-certificates

echo "[INFO] Removing rclone from apt (if present)..."
$SUDO apt-get remove -y rclone || true

echo "[INFO] Installing official rclone from rclone.org..."
curl -fsSL https://rclone.org/install.sh | $SUDO bash

echo "[INFO] Verifying that 'mega' backend is available..."
if ! rclone help backends | grep -qi '^\s*mega\b'; then
  echo "[ERROR] Installed rclone does not expose 'mega' backend." >&2
  exit 2
fi

echo "[OK] rclone installed: $(rclone --version | head -n1)"

# Optional connection test if project config exists
CONF="${RCLONE_CONF_HOST:-./env/rclone.conf}"
if [[ -f "$CONF" ]]; then
  echo "[INFO] Config found: $CONF - trying 'rclone about mega:'"
  if rclone --config "$CONF" about mega: >/dev/null 2>&1; then
    rclone --config "$CONF" about mega:
    echo "[OK] Access to remote 'mega:' successful."
  else
    echo "[WARN] 'mega:' not accessible with $CONF."
    echo "[HINT] Run: ./utils/rclone-manager.sh to create/update credentials."
  fi
else
  echo "[WARN] Project rclone config not found in $CONF."
  echo "[HINT] Run: ./utils/rclone-manager.sh to generate it."
fi

echo "[DONE] Requirements installed."
