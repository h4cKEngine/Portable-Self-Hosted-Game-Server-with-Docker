#!/bin/bash

# --- CONFIGURATION ---
# Path to the mods directory (run as ./utils/disablemods.sh on/off)
MODS_DIR="../data/mods"

# LIST OF MODS TO MANAGE
# Add here the exact names of the problematic .jar files
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

# Check if directory exists
if [ ! -d "$MODS_DIR" ]; then
    echo "Error: Directory $MODS_DIR does not exist!"
    exit 1
fi

case "$ACTION" in
    on|enable)
        echo "  DISABLING MODS..."
        for mod in "${TARGET_MODS[@]}"; do
            # If the .jar exists, rename it to .disabled
            if [ -f "$MODS_DIR/$mod" ]; then
                mv "$MODS_DIR/$mod" "$MODS_DIR/$mod.disabled"
                echo " Disabled: $mod"
            elif [ -f "$MODS_DIR/$mod.disabled" ]; then
                echo "  Already disabled: $mod"
            else
                echo " File not found: $mod"
            fi
        done
        ;;
        
    off|disable)
        echo "  ENABLING MODS..."
        for mod in "${TARGET_MODS[@]}"; do
            # If the .disabled exists, rename it to .jar
            if [ -f "$MODS_DIR/$mod.disabled" ]; then
                mv "$MODS_DIR/$mod.disabled" "$MODS_DIR/$mod"
                echo "Enabled: $mod"
            elif [ -f "$MODS_DIR/$mod" ]; then
                echo " Already active: $mod"
            else
                echo " Disabled file not found: $mod.disabled"
            fi
        done
        ;;
        
    *)
        echo "Script usage:"
        echo "  ./disablemods.sh on    -> Disable problematic mods (rename to .disabled)"
        echo "  ./disablemods.sh off   -> Re-enable mods (rename to .jar)"
        exit 1
        ;;
esac

echo "---------------------------------"
echo "Operation completed."