#!/usr/bin/env bash

# Host Agent Script
# This script runs on the WSL host and waits for commands from the web UI.

echo "=========================================================="
echo "      HOST AGENT STARTED (Waiting for web commands...)"
echo "=========================================================="
echo "Keep this terminal open while using the web dashboard."
echo "If sudo password is required, it will be prompted here."

ACTION_FILE="./action.txt"

# Ensure clean state
rm -f "$ACTION_FILE"

# Cleanly stop web container when the script/terminal closes
cleanup() {
    echo "=========================================================="
    echo "      SHUTTING DOWN DASHBOARD (Terminal Closed)"
    echo "=========================================================="
    source env/.env 2>/dev/null || true
    PROJ_NAME="${MC_CONTAINER_NAME:-minecraft-server}"
    docker compose -p "$PROJ_NAME" --env-file env/.env stop web
    exit 0
}
trap cleanup SIGINT SIGTERM SIGHUP EXIT

while true; do
    if [ -f "$ACTION_FILE" ]; then
        ACTION=$(cat "$ACTION_FILE")
        rm -f "$ACTION_FILE"
        
        if [ "$ACTION" == "start" ]; then
            echo "[$(date)] Web UI requested: START SERVER"
            ./run-server.sh -d
        elif [ "$ACTION" == "stop" ]; then
            echo "[$(date)] Web UI requested: STOP SERVER"
            # Get the container name to use as project name, defaulting to minecraft-server
            source env/.env 2>/dev/null || true
            PROJ_NAME="${MC_CONTAINER_NAME:-minecraft-server}"
            docker compose -p "$PROJ_NAME" --env-file env/.env stop mc backups
        fi
    fi
    sleep 2
done
