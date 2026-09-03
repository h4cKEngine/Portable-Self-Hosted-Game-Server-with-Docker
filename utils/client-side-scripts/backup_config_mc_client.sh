#!/bin/bash

# --- PATH CONFIGURATION ---
SOURCE="$HOME/.minecraft"
LOG_FILE="$SOURCE/logs/latest.log"
DEST_BASE="$HOME/Desktop/MC_Light_Backup"
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M")
BACKUP_PATH="$DEST_BASE/Backup_$TIMESTAMP"

echo "======================================================"
echo "           MC LIGHT BACKUP - AUTO-DETECTION"
echo "======================================================"
echo "[!] WARNING: For the backup to be complete and"
echo "    versions to be detected, Minecraft must have been"
echo "    started successfully at least once"
echo "    with mods loaded."
echo "======================================================"
echo ""

# --- LOG CHECK ---
if [[ ! -f "$LOG_FILE" ]]; then
    echo "[ERROR] Log file not found at: $LOG_FILE"
    echo "Start the game to generate it."
    exit 1
fi

# --- AUTO-DISCOVERY ---
echo "[+] Detecting versions from log file..."

# Safe extraction of versions
MC_VER=$(grep -oP "(?<=--fml.mcVersion, )[^, ]+" "$LOG_FILE" | head -n 1)
NEO_VER=$(grep -oP "(?<=--fml.neoForgeVersion, )[^, ]+" "$LOG_FILE" | head -n 1)
FORGE_VER_RAW=$(grep -oP "(?<=--fml.forgeVersion, )[^, ]+" "$LOG_FILE" | head -n 1)

if [[ -n "$NEO_VER" ]]; then
    FORGE_VER="NeoForge-$NEO_VER"
elif [[ -n "$FORGE_VER_RAW" ]]; then
    FORGE_VER="Forge-$FORGE_VER_RAW"
else
    FORGE_VER="UnknownLoader"
fi

[[ -z "$MC_VER" ]] && MC_VER="UnknownMC"

MODLIST_FILE="mods_list_MC${MC_VER}_${FORGE_VER}.txt"

echo "[+] Detected: MC $MC_VER | $FORGE_VER"

# --- BACKUP EXECUTION ---
mkdir -p "$BACKUP_PATH"

echo "[+] Generating $MODLIST_FILE..."
{
    echo "# List of Mods installed on $(date)"
    echo "# Minecraft Version: $MC_VER"
    echo "# Loader Version: $FORGE_VER"
    echo "# ------------------------------------------"
    ls -1 "$SOURCE/mods/"*.jar 2>/dev/null | xargs -n 1 basename
} > "$BACKUP_PATH/$MODLIST_FILE"

echo "[+] Synchronizing Config folder..."
if command -v rsync >/dev/null 2>&1; then
    rsync -rtv --quiet "$SOURCE/config/" "$BACKUP_PATH/config/"
else
    cp -r "$SOURCE/config/" "$BACKUP_PATH/config/"
fi

echo "[+] Copying extra files..."
[[ -f "$SOURCE/options.txt" ]] && cp "$SOURCE/options.txt" "$BACKUP_PATH/"
[[ -f "$SOURCE/servers.dat" ]] && cp "$SOURCE/servers.dat" "$BACKUP_PATH/"

echo "------------------------------------------------------"
echo "[OK] Backup completed in: $BACKUP_PATH"
echo "------------------------------------------------------"