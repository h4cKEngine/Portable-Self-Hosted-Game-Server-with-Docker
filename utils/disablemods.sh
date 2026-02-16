#!/bin/bash

# --- CONFIGURAZIONE ---
# Percorso della cartella mods (da lanciare ./utils/disablemods.sh on/off)
MODS_DIR="../data/mods"

# LISTA DELLE MOD DA GESTIRE
# Aggiungi qui i nomi esatti dei file .jar che danno problemi
TARGET_MODS=(
    "Cobblemon-neoforge-1.7.3+1.21.1.jar"
    "Cobbreeding-neoforge-2.2.0.jar"
    "cobblemonarmory-1.4.4-neoforge-1.21.1.jar"
    "cobblemonoutbreaks-neoforge-1.0.1-1.21.1.jar"
    "spawnnotification-neoforge-1.7.3-2.3.0.jar"
    "shinyfossils-0.9.2.jar"
    "fightorflight-neoforge-0.10.6.jar"
    "timcore-neoforge-1.7.3-1.31.0.jar"
    "mega_showdown-neoforge-1.6.9+1.7.3+1.21.1.jar"
)
# ----------------------

ACTION=$1

# Controllo che la cartella esista
if [ ! -d "$MODS_DIR" ]; then
    echo "Errore: La cartella $MODS_DIR non esiste!"
    exit 1
fi

case "$ACTION" in
    on|enable)
        echo "  DISABILITAZIONE MOD..."
        for mod in "${TARGET_MODS[@]}"; do
            # Se esiste il .jar, lo rinomino in .disabled
            if [ -f "$MODS_DIR/$mod" ]; then
                mv "$MODS_DIR/$mod" "$MODS_DIR/$mod.disabled"
                echo " Disabilitata: $mod"
            elif [ -f "$MODS_DIR/$mod.disabled" ]; then
                echo "  Già disabilitata: $mod"
            else
                echo " File non trovato: $mod"
            fi
        done
        ;;
        
    off|disable)
        echo "  ABILITAZIONE MOD..."
        for mod in "${TARGET_MODS[@]}"; do
            # Se esiste il .disabled, lo rinomino in .jar
            if [ -f "$MODS_DIR/$mod.disabled" ]; then
                mv "$MODS_DIR/$mod.disabled" "$MODS_DIR/$mod"
                echo "Abilitata: $mod"
            elif [ -f "$MODS_DIR/$mod" ]; then
                echo " Già attiva: $mod"
            else
                echo " File disabilitato non trovato: $mod.disabled"
            fi
        done
        ;;
        
    *)
        echo "Utilizzo dello script:"
        echo "  ./disablemods.sh on    -> Disabilita le mod problematiche (rinomina in .disabled)"
        echo "  ./disablemods.sh off   -> Riabilita le mod (rinomina in .jar)"
        exit 1
        ;;
esac

echo "---------------------------------"
echo "Operazione completata."