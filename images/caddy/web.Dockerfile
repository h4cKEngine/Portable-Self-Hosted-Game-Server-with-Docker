FROM caddy:2.8-builder-alpine AS builder

ARG CADDY_DNS_PROVIDER=duckdns

RUN xcaddy build --with github.com/caddy-dns/$CADDY_DNS_PROVIDER

FROM caddy:2.8-alpine

# Install Python, pip, rclone and Docker CLI for remote management/logging
RUN apk add --no-cache rclone python3 py3-pip docker-cli docker-cli-compose

# Install FastAPI API requirements
WORKDIR /app
COPY requirements.txt .
RUN pip install --break-system-packages --no-cache-dir -r requirements.txt

# Setup directory for persistent environment files
RUN mkdir -p /app/env

# Copy Caddy and Python API scripts
COPY --from=builder /usr/bin/caddy /usr/bin/caddy
COPY main.py .
COPY start.sh /start.sh
RUN chmod +x /start.sh

# Run the wrapper script
CMD ["/start.sh"]
