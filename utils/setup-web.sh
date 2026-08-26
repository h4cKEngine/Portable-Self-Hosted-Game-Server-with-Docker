#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Ensure env directory and base files exist
mkdir -p ./env
if [ ! -f "./env/.env" ] && [ -f "./env/.env-example" ]; then
  echo "[INFO] Creating initial env/.env from .env-example..."
  cp ./env/.env-example ./env/.env
elif [ ! -f "./env/.env" ]; then
  touch ./env/.env
fi

if [ ! -f "./env/rclone.conf" ] && [ -f "./env/rclone.conf.example" ]; then
  cp ./env/rclone.conf.example ./env/rclone.conf
elif [ ! -f "./env/rclone.conf" ]; then
  touch ./env/rclone.conf
fi

# Export environment variables from env/.env if present
if [ -f "./env/.env" ]; then
  set -a
  source "./env/.env" 2>/dev/null || true
  set +a
fi

# Ensure default fallback container name
export MC_CONTAINER_NAME="${MC_CONTAINER_NAME:-minecraft-server}"
export COMPOSE_PROJECT_NAME="${MC_CONTAINER_NAME}"

# Detect IP address
SERVER_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "127.0.0.1")
[ -z "$SERVER_IP" ] && SERVER_IP="127.0.0.1"

# Ensure external network exists for dashboard to talk to MC server
docker network create mc_network 2>/dev/null || true

COMPOSE_CMD="docker compose -p mc-dashboard -f docker-compose.dashboard.yml --env-file ./env/.env"

case "${1:-start}" in
  stop|--stop|-s|down|--down)
    echo "[INFO] Stopping Web Configurator container..."
    $COMPOSE_CMD stop web
    echo "[OK] Web Configurator container stopped."
    ;;
  restart|--restart|-r)
    echo "[INFO] Restarting Web Configurator container..."
    $COMPOSE_CMD restart web
    echo "[OK] Web Configurator container restarted."
    ;;
  status|--status|-st)
    $COMPOSE_CMD ps web
    ;;
  logs|--logs|-l)
    $COMPOSE_CMD logs -f web
    ;;
  help|--help|-h)
    echo "Usage: ./setup-web.sh [command]"
    echo ""
    echo "Commands:"
    echo "  start, --start     Start the web configurator container (default)"
    echo "  stop, --stop, -s   Stop the web configurator container"
    echo "  restart, --restart Restart the web configurator container"
    echo "  status, --status   Check status of the web container"
    echo "  logs, --logs       Follow logs of the web configurator"
    echo "  help, --help       Show this help message"
    ;;
  start|--start|*)
    echo "=========================================================="
    echo "      STARTING WEB CONFIGURATOR (CADDY + FASTAPI)"
    echo "=========================================================="
    
    # Fix for common Docker Desktop in WSL error ("docker-credential-desktop.exe not found")
    if [ -f ~/.docker/config.json ]; then
      sed -i 's/"credStore"/"credStore"/g' ~/.docker/config.json 2>/dev/null || true
    fi

    # Build and start only the web service
    $COMPOSE_CMD up -d web --build
    
    echo ""
    echo "[OK] Web Configurator container is running!"
    echo ""
    echo "  👉 Local Access:   http://localhost/config.html (or https://localhost/config.html)"
    echo "  👉 LAN/VPN Access: http://${SERVER_IP}/config.html"
    echo "  👉 Status Page:    http://localhost/index.html (or https://localhost/index.html)"
    echo ""
    echo "Configure your server in the browser and click 'Save Configuration'."
    echo "After saving ./env/.env, you can start the game server with: ./run-server.sh"
    echo "To stop the web configurator: ./setup-web.sh --stop"
    echo "=========================================================="
    ;;
esac
