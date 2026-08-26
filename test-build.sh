#!/bin/bash
docker run --rm caddy:2.8-builder-alpine sh -c "xcaddy build --with github.com/caddy-dns/duckdns@v0.4.0"
