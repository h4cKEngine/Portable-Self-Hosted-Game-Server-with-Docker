#!/bin/bash

# --- CONFIGURAZIONE PERCORSI ---
SOURCE="$HOME/.minecraft"
LOG_FILE="$SOURCE/logs/latest.log"
DEST_BASE="$HOME/Desktop/MC_Light_Backup"
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M")
BACKUP_PATH="$DEST_BASE/Backup_$TIMESTAMP"

echo "======================================================"
echo "           MC LIGHT BACKUP - AUTO-DETECTION"
echo "======================================================"
echo "[!] AVVISO: Affinche il backup sia completo e le"
echo "    versioni vengano rilevate, Minecraft deve essere"
echo "    stato avviato correttamente almeno una volta"
echo "    con le mod caricate."
echo "======================================================"
echo ""

# --- CONTROLLO LOG ---
if [[ ! -f "$LOG_FILE" ]]; then
    echo "[ERRORE] File di log non trovato in: $LOG_FILE"
    echo "Avvia il gioco per generarlo."
    exit 1
fi

# --- AUTO-DISCOVERY ---
echo "[+] Rilevamento versioni dal file di log..."

# Estrazione sicura delle versioni
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

echo "[+] Rilevato: MC $MC_VER | $FORGE_VER"

# --- ESECUZIONE BACKUP ---
mkdir -p "$BACKUP_PATH"

echo "[+] Generazione $MODLIST_FILE..."
{
    echo "# Elenco Mod installate al $(date)"
    echo "# Minecraft Version: $MC_VER"
    echo "# Loader Version: $FORGE_VER"
    echo "# ------------------------------------------"
    ls -1 "$SOURCE/mods/"*.jar 2>/dev/null | xargs -n 1 basename
} > "$BACKUP_PATH/$MODLIST_FILE"

echo "[+] Sincronizzazione cartella Config..."
if command -v rsync >/dev/null 2>&1; then
    rsync -rtv --quiet "$SOURCE/config/" "$BACKUP_PATH/config/"
else
    cp -r "$SOURCE/config/" "$BACKUP_PATH/config/"
fi

echo "[+] Copia file extra..."
[[ -f "$SOURCE/options.txt" ]] && cp "$SOURCE/options.txt" "$BACKUP_PATH/"
[[ -f "$SOURCE/servers.dat" ]] && cp "$SOURCE/servers.dat" "$BACKUP_PATH/"

echo "------------------------------------------------------"
echo "[OK] Backup completato in: $BACKUP_PATH"
echo "------------------------------------------------------"