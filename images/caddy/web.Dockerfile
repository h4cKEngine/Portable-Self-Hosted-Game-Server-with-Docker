FROM caddy:2.10-builder-alpine AS builder

ARG CADDY_DNS_PROVIDER=duckdns

RUN xcaddy build --with github.com/caddy-dns/$CADDY_DNS_PROVIDER

FROM caddy:2.10-alpine

# Install Python, pip, rclone, bash and Docker CLI for remote management/logging
RUN apk add --no-cache rclone python3 py3-pip docker-cli docker-cli-compose bash 7zip build-base && \
    wget https://www.rarlab.com/rar/unrarsrc-7.0.1.tar.gz && \
    tar -xzf unrarsrc-7.0.1.tar.gz && \
    cd unrar && make -j$(nproc) && make install && \
    cd .. && rm -rf unrar unrarsrc-7.0.1.tar.gz && \
    apk del build-base
# Install FastAPI API requirements
WORKDIR /app
COPY requirements.txt .
RUN pip install --break-system-packages --no-cache-dir -r requirements.txt

# Setup directory for persistent environment files and Caddy assets
RUN mkdir -p /app/env /etc/caddy /usr/share/caddy

# Copy Caddy and Python API scripts
COPY --from=builder /usr/bin/caddy /usr/bin/caddy
COPY Caddyfile /etc/caddy/Caddyfile
COPY web /usr/share/caddy
COPY main.py .
COPY start.sh /start.sh
RUN chmod +x /start.sh

# Run the wrapper script
CMD ["/start.sh"]
