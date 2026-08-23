#!/bin/sh

# Start the Python FastAPI in the background with auto-reload
cd /app
uvicorn main:app --host 127.0.0.1 --port 8000 --reload &

# Start Caddy in the foreground as main process
exec caddy run --config /etc/caddy/Caddyfile --adapter caddyfile
