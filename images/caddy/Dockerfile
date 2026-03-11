FROM caddy:builder-alpine AS builder

ARG CADDY_DNS_PROVIDER=duckdns

RUN xcaddy build --with github.com/caddy-dns/$CADDY_DNS_PROVIDER

FROM caddy:alpine

# Install Python and pip
RUN apk add --no-cache python3 py3-pip

# Install FastAPI API requirements
WORKDIR /app
COPY requirements.txt .
RUN pip install --break-system-packages --no-cache-dir -r requirements.txt

# Copy Caddy and Python API scripts
COPY --from=builder /usr/bin/caddy /usr/bin/caddy
COPY main.py .
COPY start.sh /start.sh
RUN chmod +x /start.sh

# Run the wrapper script
CMD ["/start.sh"]
