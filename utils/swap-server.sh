#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# === Helpers ===
log()  { echo "[INFO] $*"; }
warn() { echo "[WARN] $*" >&2; }
err()  { echo "[ERROR] $*" >&2; exit 1; }

# Determine current server name
if [[ ! -f "env/.env" ]]; then
    err "File env/.env non trovato. Il server non è stato inizializzato."
fi

# Load current MC_CONTAINER_NAME
CURRENT_SERVER=$(grep -E "^MC_CONTAINER_NAME=" env/.env | cut -d '=' -f 2- | tr -d '"' | tr -d "'" || true)
if [[ -z "$CURRENT_SERVER" ]]; then
    CURRENT_SERVER="minecraft-server"
fi

if [[ $# -eq 0 ]]; then
    log "Uso: ./swap-server.sh <nuovo_nome_server>"
    log "Server attualmente attivo: $CURRENT_SERVER"
    echo ""
    log "Server salvati in servers_played/:"
    if [[ -d "servers_played" ]]; then
        ls -1 servers_played/ | sed 's/^/  - /' || echo "  (Nessuno)"
    else
        echo "  (Nessuno)"
    fi
    exit 0
fi

TARGET_SERVER="$1"

if [[ "$CURRENT_SERVER" == "$TARGET_SERVER" ]]; then
    log "Il server '$TARGET_SERVER' è già quello attivo."
    exit 0
fi

# 1. Verifica container attivi
if docker ps --format '{{.Names}}' | grep -q "^${CURRENT_SERVER}$"; then
    log "Il container del server attuale ($CURRENT_SERVER) è in esecuzione."
    read -p "Vuoi fermarlo ora con 'docker compose stop'? (y/N) " resp
    case "$resp" in
        [yY]*) 
            log "Fermo i container..."
            docker compose stop
            ;;
        *) 
            err "Operazione annullata. Ferma i container prima di scambiare il server."
            ;;
    esac
fi

# 2. Salvataggio Server Attuale
log "=== Salvataggio del server attuale: $CURRENT_SERVER ==="
mkdir -p "servers_played/$CURRENT_SERVER/env"

if [[ -d "data" ]]; then
    log "Sposto cartella ./data -> servers_played/$CURRENT_SERVER/data"
    if [[ -d "servers_played/$CURRENT_SERVER/data" ]]; then
        rmdir "servers_played/$CURRENT_SERVER/data" 2>/dev/null || warn "servers_played/$CURRENT_SERVER/data non è vuota, possibile sovrascrittura in corso..."
    fi
    mv data "servers_played/$CURRENT_SERVER/"
fi

log "Copio ./env/ -> servers_played/$CURRENT_SERVER/env/"
cp -a env/. "servers_played/$CURRENT_SERVER/env/"


# 3. Caricamento Nuovo Server
log "=== Caricamento del nuovo server: $TARGET_SERVER ==="
mkdir -p "servers_played/$TARGET_SERVER/env"

if [[ -d "servers_played/$TARGET_SERVER/data" ]]; then
    log "Sposto cartella servers_played/$TARGET_SERVER/data -> ./data"
    mv "servers_played/$TARGET_SERVER/data" ./data
else
    log "Creo nuova cartella ./data vuota per il nuovo server."
    mkdir -p data
fi

if [[ -f "servers_played/$TARGET_SERVER/env/.env" ]]; then
    log "Ripristino ./env/ da servers_played/$TARGET_SERVER/env/"
    rm -f ./env/* ./env/.* 2>/dev/null || true
    cp -a "servers_played/$TARGET_SERVER/env/." ./env/ 2>/dev/null || true
else
    log "Nuovo server: creo configurazione di base da env/.env-example"
    cp "env/.env-example" "./env/.env"
    
    # Update MC_CONTAINER_NAME and others
    sed -i "s/^MC_CONTAINER_NAME=.*/MC_CONTAINER_NAME=${TARGET_SERVER}/" ./env/.env
    sed -i "s/^RESTIC_TAG=.*/RESTIC_TAG=${TARGET_SERVER}_backups/" ./env/.env
    
    # Attempt to replace the suffix of MUTEX_REMOTE_DIR and RESTIC_REPOSITORY
    sed -i "s|^\(RESTIC_REPOSITORY=[^:]*:[^:]*:\/\).*|\1${TARGET_SERVER}|" ./env/.env
    sed -i "s|^\(MUTEX_REMOTE_DIR=[^:]*:\/\).*|\1${TARGET_SERVER}|" ./env/.env
    
    # Also update MOTD
    sed -i "s/^MOTD=.*/MOTD=\"§6${TARGET_SERVER} §7| §bNuovo Server\"/" ./env/.env
    
    log "Configurazione .env per $TARGET_SERVER inizializzata. Puoi modificarla tramite la Dashboard Web."
fi

log "Scambio completato con successo! Server attivo: $TARGET_SERVER"
