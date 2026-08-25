#!/usr/bin/env bash
cd "$(dirname "$0")"

echo "=========================================================="
echo "      STARTING GAME SERVER DASHBOARD"
echo "=========================================================="
echo "Starting web container and host agent..."

# Ensure execution permissions
chmod +x *.sh utils/*.sh

# Start the web interface
./setup-web.sh

# Try to open the browser automatically
if command -v xdg-open &> /dev/null; then
    xdg-open http://localhost/index.html &> /dev/null &
elif command -v open &> /dev/null; then
    open http://localhost/index.html &> /dev/null &
fi

# Run the host agent in the foreground
./utils/host-agent.sh
