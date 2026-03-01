#!/bin/bash
set -euo pipefail

# ==============================================================================
# 0. CONSTANTS & VARIABLES
# ==============================================================================
ENV_FILE="env/.env"
TEMPLATE_FILE="env/env"

# Colors
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Flags
SHOW_ADVANCED=true
INTERACTIVE=true
DO_REINSTALL=false

# ==============================================================================
# 1. UTILITY FUNCTIONS
# ==============================================================================
# Prints an info message in green
msg()  { printf "${GREEN}[INFO] %s${NC}\n" "$*"; }
info() { printf "${CYAN}%b${NC}" "$*"; }
warn() { printf "${YELLOW}[WARN] %s${NC}\n" "$*"; }

# Prompts the user for input with a default value
ask() {
  local prompt="$1"
  local var_name="$2"
  local default_val="$3"
  
  # Print prompt
  info "${prompt}\n"
  
  # Read with default
  local input
  read -e -i "${default_val}" -p ": " input
  
  # Assign to the dynamic variable name
  printf -v "$var_name" "%s" "$input"
}

# Prompts the user for a choice among fixed options
ask_choice() {
  local prompt="$1"
  local var_name="$2"
  local default_val="$3"
  local allowed_values="$4" # Space-separated list

  while true; do
    # Print prompt with allowed values
    info "${prompt}\n"
    info "(Allowed choices: ${allowed_values})\n"
    
    # Read with default
    local input
    read -e -i "${default_val}" -p ": " input
    
    # Normalize to uppercase for comparison (optional, but good for UX)
    input=$(echo "$input" | tr '[:lower:]' '[:upper:]')

    # Validate
    local valid=false
    for val in $allowed_values; do
      if [ "$input" = "$val" ]; then
        valid=true
        break
      fi
    done

    if [ "$valid" = true ]; then
      printf -v "$var_name" "%s" "$input"
      break
    else
      warn "Invalid input: '$input'. Try again."
    fi
  done
}

# Prompts the user with regex validation
ask_pattern() {
  local prompt="$1"
  local var_name="$2"
  local default_val="$3"
  local pattern="$4"
  local error_msg="${5:-Invalid input for the requested pattern}"

  while true; do
    # Print prompt
    info "${prompt}\n"
    
    # Read with default
    local input
    read -e -i "${default_val}" -p ": " input
    
    # Check if empty (use default logic handled by read -i, but if user explicitly clears it?)
    # read -i provides the default in the buffer. If user deletes it, input is empty.
    # In this script, often empty means "skip" or "use default".
    # BUT logic says "if input entered ... value must be valid".
    # If user deletes default and sends empty:
    #   If default was non-empty, maybe we should enforce non-empty?
    #   For "optional" fields (like RCON), empty might be valid if pattern allows it.
    
    if [ -z "$input" ]; then
        # If input is empty, we check if pattern matches empty string or if we accept it.
        # But commonly, variables have defaults.
        # If variable is mandatory, pattern should exclude empty.
        if [[ "" =~ $pattern ]]; then
             printf -v "$var_name" "%s" ""
             break
        else
             # If pattern doesn't allow empty, and default exists, user probably cleared it.
             # Warn and retry.
             warn "Value cannot be empty."
             continue
        fi
    fi

    if [[ "$input" =~ $pattern ]]; then
      printf -v "$var_name" "%s" "$input"
      break
    else
      warn "$error_msg"
      warn "Required pattern: $pattern"
    fi
  done
}

# Converts a string to a slug format
slugify() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | tr -cd '[:alnum:]_-'
}

# ==============================================================================
# 2. CORE FUNCTIONS
# ==============================================================================
# Parses command line arguments
parse_args() {
  for arg in "$@"; do
    case $arg in
      --noasking)           INTERACTIVE=false ;;
      -f|--full|--advanced) SHOW_ADVANCED=true ;;
      --reinstall)          DO_REINSTALL=true ;;
    esac
  done
}

# Determines if a configuration block should be executed
should_configure_block() {
  local block_name="$1"
  # If INTERACTIVE=false (e.g. --noasking), always assume YES
  if [ "$INTERACTIVE" = false ]; then
    return 0
  fi
  
  echo ""
  read -p "Do you want to configure/modify the [${block_name}] section? [Y/n] " ANSWER
  if [[ "${ANSWER:-Y}" =~ ^[Yy]$ ]]; then
    return 0
  else
    return 1
  fi
}

# Removes Zone.Identifier files (WSL artifact)
clean_identifiers() {
  echo ">>> (0/5) Removing all Zone.Identifier files..."
  if [[ -f ./utils/delete-all-zone-identifier.sh ]]; then
    bash ./utils/delete-all-zone-identifier.sh
  else
    warn "Zone.Identifier script not found, skipping."
  fi
}

# Initializes data directory structure
init_data_dirs() {
  echo ">>> (0.5/5) Initializing 'data/' directory structure..."
  local dirs="data/mods data/config data/libraries data/logs data/world"
  
  for d in $dirs; do
    if [[ ! -d "$d" ]]; then
      echo "    + Creating directory: $d"
      mkdir -p "$d"
    fi
  done
}

# Checks and installs dependencies
check_deps() {
  echo ">>> (1/5) Checking Dependencies..."
  if [ "$DO_REINSTALL" = true ]; then
     echo "    (Reinstall Mode: ON - Previous uninstallation...)"
     bash ./utils/requirements.sh uninstall || true
     echo ""
  fi

  bash ./utils/requirements.sh || {
    warn "Error during requirements installation."
    read -p "Do you want to continue anyway? [y/N] " CONT
    if [[ ! "${CONT:-N}" =~ ^[Yy]$ ]]; then exit 1; fi
  }
}

# Loads default values from .env or template
load_defaults() {
  if [ -f "$ENV_FILE" ]; then
    msg ".env file found. Loading existing values..."
    set -a; source "$ENV_FILE" 2>/dev/null || true; set +a
  elif [ -f "$TEMPLATE_FILE" ]; then
    msg ".env file not found. Using $TEMPLATE_FILE as base..."
    set -a; source "$TEMPLATE_FILE" 2>/dev/null || true; set +a
  fi
}

# Configures server settings (Version, Type, IP, etc.)
config_server() {
  echo ""
  echo ">>> (2/5) Server Configuration (Minecraft/IP)"
  
  if should_configure_block "Server & IP"; then
    ask_pattern "1. Modpack Name (e.g. 'tekkit', 'vanilla')" \
       INPUT_NAME "${MC_CONTAINER_NAME:-minecraft}" \
       "^[a-zA-Z0-9_-]+$" \
       "Use only letters, numbers, hyphens (-) or underscores (_)."
    INPUT_NAME="$(slugify "$INPUT_NAME")"
  
    ask_pattern "\n2. Minecraft Version (e.g. '1.12.2', '1.20.1')" \
       INPUT_VERSION "${VERSION:-1.12.2}" \
       "^[a-zA-Z0-9.-]+$" \
       "Invalid version."
        
    ask_choice "\n3. Server Type" \
        INPUT_TYPE "${TYPE:-FORGE}" "VANILLA FORGE FABRIC NEOFORGE"
    
    ask_pattern "\n4. Server Public IP/VPN (e.g. '1.2.3.4')" \
        INPUT_IP "${IP_SERVER:-127.0.0.1}" \
        "^[a-zA-Z0-9.-]+$" \
        "Invalid IP address or Hostname."

    # Advanced Server Params (Mem, Forge, Seeds, RCON, MOTD, OPS)
    INPUT_FORGE="${FORGE_VERSION:-}"
    INPUT_NEOFORGE="${NEOFORGE_VERSION:-}"
    INPUT_FABRIC_LAUNCHER="${FABRIC_LAUNCHER_VERSION:-}"
    INPUT_FABRIC_LOADER="${FABRIC_LOADER_VERSION:-}"
    INPUT_MEM_INIT="${INIT_MEMORY:-2G}"
    INPUT_MEM_MAX="${MEMORY:-6G}"
    INPUT_SEED="${SEED:-}"
    INPUT_RCON="${RCON_PASSWORD:-minecraft}"
    INPUT_MOTD="${MOTD:-}"
    INPUT_OPS="${OPERATORS:-}"
    INPUT_VIEW_DISTANCE="${VIEW_DISTANCE:-15}"
    INPUT_SIMULATION_DISTANCE="${SIMULATION_DISTANCE:-5}"

    # Ask for specific versions based on TYPE
    case "$INPUT_TYPE" in
      FORGE)
          ask_pattern "\nForge Version (empty=auto)" \
            INPUT_FORGE "${FORGE_VERSION:-}" \
            "^[a-zA-Z0-9.-]*$" "Invalid version."
          ;;
      NEOFORGE)
          ask_pattern "\nNeoForge Version (empty=auto, default=auto)" \
            INPUT_NEOFORGE "${NEOFORGE_VERSION:-}" \
            "^[a-zA-Z0-9.-]*$" "Invalid version."
          ;;
      FABRIC)
          ask_pattern "\nFabric Launcher Version (empty=auto)" \
            INPUT_FABRIC_LAUNCHER "${FABRIC_LAUNCHER_VERSION:-}" \
            "^[a-zA-Z0-9.-]*$" "Invalid version."
          ask_pattern "Fabric Loader Version (empty=auto)" \
             INPUT_FABRIC_LOADER "${FABRIC_LOADER_VERSION:-}" \
             "^[a-zA-Z0-9.-]*$" "Invalid version."
          ;;
      VANILLA)
          info "Vanilla selected. Using standard Minecraft Version ($INPUT_VERSION)."
          ;;
    esac

    if [ "$SHOW_ADVANCED" = true ]; then
      info "\n--- Advanced Server Settings ---\n"
      # (Forge/NeoForge/Fabric params already asked above based on TYPE)
      
      ask_pattern "\nInitial RAM (e.g. 2G, 512M)" \
          INPUT_MEM_INIT "${INIT_MEMORY:-2G}" \
          "^[0-9]+[MmGg]$" "Invalid RAM format. Use M (Megabyte) or G (Gigabyte)."
      
      ask_pattern "\nMaximum RAM (e.g. 6G)" \
          INPUT_MEM_MAX "${MEMORY:-6G}" \
          "^[0-9]+[MmGg]$" "Invalid RAM format."
      
      ask_pattern "\nWorld Seed" \
          INPUT_SEED "${SEED:-}" \
          "^[a-zA-Z0-9_-]*$" "Invalid seed."
      
      ask "\nRCON Password"                      INPUT_RCON "${RCON_PASSWORD:-minecraft}"
      ask "\nMOTD (leave empty for auto)"       INPUT_MOTD "${MOTD:-}"
      ask "\nOPS (Admin - comma separated)"   INPUT_OPS "${OPERATORS:-}"
      ask_pattern "\nView Distance"              INPUT_VIEW_DISTANCE "${VIEW_DISTANCE:-15}" "^[0-9]+$" "Enter an integer."
      ask_pattern "\nSimulation Distance"        INPUT_SIMULATION_DISTANCE "${SIMULATION_DISTANCE:-5}" "^[0-9]+$" "Enter an integer."
    fi
  else
    # Keep old values if skipped
    INPUT_NAME="${MC_CONTAINER_NAME:-minecraft}"
    INPUT_VERSION="${VERSION:-1.12.2}"
    INPUT_TYPE="${TYPE:-FORGE}"
    INPUT_IP="${IP_SERVER:-127.0.0.1}"
    
    INPUT_FORGE="${FORGE_VERSION:-}"
    INPUT_NEOFORGE="${NEOFORGE_VERSION:-}"
    INPUT_FABRIC_LAUNCHER="${FABRIC_LAUNCHER_VERSION:-}"
    INPUT_FABRIC_LOADER="${FABRIC_LOADER_VERSION:-}"
    INPUT_MEM_INIT="${INIT_MEMORY:-2G}"
    INPUT_MEM_MAX="${MEMORY:-6G}"
    INPUT_SEED="${SEED:-}"
    INPUT_RCON="${RCON_PASSWORD:-minecraft}"
    INPUT_MOTD="${MOTD:-}"
    INPUT_OPS="${OPERATORS:-}"
    INPUT_VIEW_DISTANCE="${VIEW_DISTANCE:-15}"
    INPUT_SIMULATION_DISTANCE="${SIMULATION_DISTANCE:-5}"
    
    info "Server block skipped. Keeping current values."
  fi
}

# Configures Rclone service
config_rclone() {
  echo ""
  echo ">>> (Cloud Configuration completed in previous steps)"
  echo "(Rclone)"

  # Try to detect default
  DEFAULT_RCLONE="mega"
  if [ -f "$RCLONE_CONFIG" ]; then
    DETECTED_REMOTE=$(grep -oP '^\[\K[^\]]+' "$RCLONE_CONFIG" | head -n1 || true)
    [ -n "$DETECTED_REMOTE" ] && DEFAULT_RCLONE="$DETECTED_REMOTE"
  fi
  
  if should_configure_block "Rclone"; then
    if [ "$SHOW_ADVANCED" = true ]; then
       # Full mode: proceed directly
       : 
    else
        # Basic mode: User said YES to block.
        # Check if config exists
        if [ ! -f "$RCLONE_CONFIG" ]; then
            warn "Rclone configuration file not found at $RCLONE_CONFIG"
            warn "It is recommended to use the Rclone Manager to configure a remote."
        else
            info "Configuration file found: $RCLONE_CONFIG\n"
            info "Available remotes:\n"
            # Extract and list remotes nicely
            if grep -qP '^\[[^\]]+\]$' "$RCLONE_CONFIG"; then
                grep -oP '^\[\K[^\]]+' "$RCLONE_CONFIG" | while read -r remote; do
                    echo "      - $remote"
                done
            else
                warn "      (none found in the file)"
            fi
        fi
        
        info "\nIf you haven't configured a remote yet or want to modify them:"
        read -p "Do you want to open the Rclone Manager now? [Y/n] " DO_MGR
        if [[ "${DO_MGR:-Y}" =~ ^[Yy]$ ]]; then
            ./utils/rclone-manager.sh
            # Re-detect default after manager
             if [ -f "$RCLONE_CONFIG" ]; then
                DETECTED_REMOTE=$(grep -oP '^\[\K[^\]]+' "$RCLONE_CONFIG" | head -n1 || true)
                [ -n "$DETECTED_REMOTE" ] && DEFAULT_RCLONE="$DETECTED_REMOTE"
             fi
        fi
    fi

    echo ""
    info "Enter the remote name to use for backup/sync."
    info "(Must exactly match the name in brackets in rclone.conf)"
    ask "Nome Remote Rclone (es. 'mega', 'drive'...)" INPUT_RCLONE_SERVICE "$DEFAULT_RCLONE"
  else
    # Logic to extrapolate service name if skipped
    if [[ "${RESTIC_REPOSITORY:-}" =~ rclone:([^:]+):/ ]]; then
        INPUT_RCLONE_SERVICE="${BASH_REMATCH[1]}"
    else
        INPUT_RCLONE_SERVICE="mega"
    fi
     info "Rclone block skipped. Using service: $INPUT_RCLONE_SERVICE"
  fi
}

# Configures Dynamic DNS
config_ddns() {
  echo ""
  echo ">>> (4/5) DDNS Configuration"
  
  INPUT_DDNS_PROVIDER="${DDNS_PROVIDER:-}"
  INPUT_DDNS_DOMAIN="${DDNS_DOMAIN:-}"
  INPUT_DDNS_TOKEN="${DDNS_TOKEN:-}"
  
  if should_configure_block "DDNS"; then
      info "Supported providers (details in README):\n"
      echo "    - Desec.io   (Score: 9.5/10) - Secure, API focus, no simple GUI."
      echo "    - Dynu       (Score: 9/10)   - Balanced, no expiration."
      echo "    - YDNS       (Score: 8.5/10) - EU Hosting, clean."
      echo "    - DuckDNS    (Score: 8/10)   - Simple, but variable downtime."
      echo "    - FreeDNS    (Score: 7.5/10) - Blacklist risk on shared domains."
      echo "    - No-IP      (Score: 6/10)   - Requires manual confirmation every 30 days."
      echo ""
      info "Leave the provider empty to DISABLE DDNS.\n"
      
      # Ask specific details
      ask "DDNS Provider" INPUT_DDNS_PROVIDER "${DDNS_PROVIDER:-duckdns}"
      
      # Normalize Provider: lower case and strip extensions (duckdns.org -> duckdns)
      INPUT_DDNS_PROVIDER=$(echo "$INPUT_DDNS_PROVIDER" | tr '[:upper:]' '[:lower:]')
      INPUT_DDNS_PROVIDER="${INPUT_DDNS_PROVIDER%%.*}"

      if [ -n "$INPUT_DDNS_PROVIDER" ]; then
          ask_pattern "DDNS Domain (es. mydomain)" INPUT_DDNS_DOMAIN "${DDNS_DOMAIN:-exampleddns}" \
               "^[a-zA-Z0-9.-]+$" "Invalid domain."
          
          echo ""
          info "Notes on Token:\n"
          info " - DuckDNS: only the token\n"
          info " - Desec/YDNS/No-IP/FreeDNS: Often require 'username:password' or specific token.\n"
          ask "DDNS Token (o Password/Key)"  INPUT_DDNS_TOKEN "${DDNS_TOKEN:-CHANGE_ME}"
      else
          info "DDNS disabled (empty provider)."
          INPUT_DDNS_DOMAIN=""
          INPUT_DDNS_TOKEN=""
      fi
  else
      info "DDNS block skipped."
  fi
}

# Configures Restic Backup settings
config_restic() {
  echo ""
  echo ">>> (5/5) Backup Configuration (Restic)"
  
  INPUT_RESTIC_HOSTNAME="${RESTIC_HOSTNAME:-Mondo}"
  INPUT_RESTIC_PASSWORD="${RESTIC_PASSWORD:-minecraft}"
  INPUT_RESTIC_KEEP_LAST="${RESTIC_KEEP_LAST:-10}"
  
  if should_configure_block "Backup/Restic"; then
      ask_pattern "Restic Hostname (Unique name for this backup)" \
          INPUT_RESTIC_HOSTNAME "${RESTIC_HOSTNAME:-Mondo}" \
          "^[a-zA-Z0-9_-]+$" "Invalid hostname."
      
      ask "Restic Password (Encryption key for the repo)"     INPUT_RESTIC_PASSWORD "${RESTIC_PASSWORD:-minecraft}"
      
      ask_pattern "Restic Keep Last (Number of snapshots to keep)" \
          INPUT_RESTIC_KEEP_LAST "${RESTIC_KEEP_LAST:-10}" \
          "^[0-9]+$" "Enter a positive integer."
  else
      # Defaults if skipped
      INPUT_RESTIC_KEEP_LAST="${RESTIC_KEEP_LAST:-10}"
      info "Backup block skipped."
  fi
}

# Computes derived variables based on user input
compute_derived() {
  FINAL_CONTAINER_NAME="$INPUT_NAME"
  FINAL_RESTIC_TAG="${INPUT_NAME}_backups"
  # Note: RESTIC_REPOSITORY must have rclone: prefix to be compatible with our containerized scripts
  FINAL_RESTIC_REPO="rclone:${INPUT_RCLONE_SERVICE}:/${INPUT_NAME}"
  
  # Mutex path for rclone-mutex.sh
  FINAL_MUTEX_DIR="${INPUT_RCLONE_SERVICE}:/${INPUT_NAME}"

  if [ -z "$INPUT_MOTD" ]; then
    FINAL_MOTD="§6${FINAL_CONTAINER_NAME} §7| §bForge ${INPUT_VERSION}"
  else
    FINAL_MOTD="$INPUT_MOTD"
  fi
}

# Confirms settings and writes to .env file
confirm_and_write() {
  msg "\nConfiguration Summary:"
  echo "------------------------------------------------"
  echo "Modpack Name:      $FINAL_CONTAINER_NAME"
  echo "Minecraft Version: $INPUT_VERSION"
  echo "Server Type:       $INPUT_TYPE"
  echo "IP Server:         $INPUT_IP"
  echo "Rclone Service:    $INPUT_RCLONE_SERVICE"
  [ "$SHOW_ADVANCED" = true ] && echo "(+ Advanced parameters)" || echo "(Advanced parameters hidden)"
  echo "------------------------------------------------"

  read -p "Save to $ENV_FILE? [Y/n] " REPLY
  if [[ ! "${REPLY:-Y}" =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
  fi

  mkdir -p env
  cat > "$ENV_FILE" <<EOF
# Generated by install_and_configure.sh on $(date)

# === Network ===
IP_SERVER=${INPUT_IP}
DDNS_DOMAIN=${INPUT_DDNS_DOMAIN}
DDNS_TOKEN=${INPUT_DDNS_TOKEN}
DDNS_PROVIDER=${INPUT_DDNS_PROVIDER}

# === RCON ===
RCON_PASSWORD=${INPUT_RCON}
BACKUP=true

# === Server Properties ===
VERSION=${INPUT_VERSION}
TYPE=${INPUT_TYPE}
FORGE_VERSION=${INPUT_FORGE}
NEOFORGE_VERSION=${INPUT_NEOFORGE}
FABRIC_LAUNCHER_VERSION=${INPUT_FABRIC_LAUNCHER}
FABRIC_LOADER_VERSION=${INPUT_FABRIC_LOADER}
INIT_MEMORY=${INPUT_MEM_INIT}
MEMORY=${INPUT_MEM_MAX}
MAX_PLAYERS=${MAX_PLAYERS:-8}
MOTD="${FINAL_MOTD}"
SEED=${INPUT_SEED}
OPERATORS=${INPUT_OPS}
VIEW_DISTANCE=${INPUT_VIEW_DISTANCE}
SIMULATION_DISTANCE=${INPUT_SIMULATION_DISTANCE}
EULA=TRUE
ONLINE_MODE=FALSE

# === Restic Backup ===
RESTIC_HOSTNAME=${INPUT_RESTIC_HOSTNAME}
RESTIC_PASSWORD=${INPUT_RESTIC_PASSWORD}
RESTIC_REPOSITORY=${FINAL_RESTIC_REPO}
RESTIC_TAG=${FINAL_RESTIC_TAG}
RESTIC_KEEP_LAST=${INPUT_RESTIC_KEEP_LAST}
RESTIC_IMAGE=${RESTIC_IMAGE:-docker.io/tofran/restic-rclone:0.17.0_1.68.2}

# === AutoStop / AutoPause ===
# ENABLE_AUTOSTOP=TRUE
# AUTOSTOP_TIMEOUT_EST=3600
# AUTOSTOP_TIMEOUT_INIT=1800
#
# ENABLE_AUTOPAUSE=TRUE
# MAX_TICK_TIME=-1
PAUSE_WHEN_EMPTY_SECONDS=300

# === Rclone ===
RCLONE_CONFIG=${RCLONE_CONFIG:-/root/.config/rclone/rclone.conf}
RCLONE_CONF_HOST=./env/rclone.conf

# === Mutex (Locking) ===
MUTEX_REMOTE_DIR=${FINAL_MUTEX_DIR}

# === Docker Compose Names ===

MC_CONTAINER_NAME=${FINAL_CONTAINER_NAME}
EOF
  msg "File saved!"

  # Prompt for Restic Initialization
  if [ "$INTERACTIVE" = true ]; then
      echo ""
      read -p "Do you want to initialize the Restic repository now? (Do this if it's the first time) [Y/n] " DO_INIT
      if [[ "${DO_INIT:-Y}" =~ ^[Yy]$ ]]; then
          if [ -f "./utils/restic-tools.sh" ]; then
             # Use || true to prevent script exit if repo already exists
             bash ./utils/restic-tools.sh init || warn "Initialization failed (maybe the repo already exists?)"
          else
             warn "Script ./utils/restic-tools.sh not found. Cannot initialize."
          fi
      fi

      echo ""
      read -p "Do you want to verify the repository status (snapshots)? [Y/n] " DO_CHECK
      if [[ "${DO_CHECK:-Y}" =~ ^[Yy]$ ]]; then
          if [ -f "./utils/restic-tools.sh" ]; then
             msg "Verifying repository status..."
             bash ./utils/restic-tools.sh doctor || warn "Verification failed or no snapshot found."
          else
             warn "Script not found."
          fi
      fi
  fi
}

# ==============================================================================
# 3. MAIN
# ==============================================================================
# Main entry point of the script
main() {
  parse_args "$@"
  clean_identifiers
  init_data_dirs
  check_deps
  
  load_defaults
  
  echo "=========================================================="
  echo "    DISTRIBUTED MINECRAFT SERVER - SETUP WIZARD"
  [ "$INTERACTIVE" = false ] && echo "    (No-Asking Mode: ON - skip confirm block)" || echo "    (Interactive Mode: Default - confirms active)"
  echo "=========================================================="
  
  config_server
  config_rclone
  config_ddns
  config_restic
  
  compute_derived
  confirm_and_write
  
  sudo apt autoremove -y
  sudo apt clean

  # Fix permissions on ./data so run-server.sh can work without sudo
  msg "\n(Fix Permissions) Setting ownership of ./data and ./run-server.sh to $USER..."
  sudo chown -R "$USER:$USER" ./data
  sudo chmod 755 -R ./data
  sudo chmod 755 ./run-server.sh
  sudo chown -R "$USER:$USER" ./data
  sudo chmod 755 -R ./world

  msg "\nSetup Completed!"
}

main "$@"
