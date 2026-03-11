#!/bin/sh

# Start the Python FastAPI in the background
cd /app
uvicorn main:app --host 127.0.0.1 --port 8000 &

# Start Caddy in the foreground
caddy run --config /etc/caddy/Caddyfile --adapter caddyfile
