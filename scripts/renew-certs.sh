#!/bin/bash
# Renewal hook for Valkey SSL certificates
# This script is called by certbot after renewal
#
# Setup:
#   1. Update DOMAIN and VALKEY_DIR below
#   2. Link to certbot hooks:
#      sudo ln -sf /path/to/valkey-ssl/scripts/renew-certs.sh \
#        /etc/letsencrypt/renewal-hooks/deploy/valkey-ssl.sh

# Configuration - UPDATE THESE
DOMAIN="${DOMAIN:-your-domain.com}"
VALKEY_DIR="${VALKEY_DIR:-/path/to/valkey-ssl}"

# Derived paths
CERTS_DIR="$VALKEY_DIR/certs"
LE_LIVE="/etc/letsencrypt/live/$DOMAIN"

# Verify Let's Encrypt certs exist
if [ ! -f "$LE_LIVE/fullchain.pem" ]; then
    echo "Error: Let's Encrypt certs not found at $LE_LIVE"
    exit 1
fi

# Copy new certs
cp "$LE_LIVE/fullchain.pem" "$CERTS_DIR/valkey.crt"
cp "$LE_LIVE/privkey.pem" "$CERTS_DIR/valkey.key"

# Fix permissions
chmod 644 "$CERTS_DIR/valkey.crt" "$CERTS_DIR/valkey.key"

# Restart Valkey to load new certs
cd "$VALKEY_DIR"
docker compose restart

echo "$(date): Valkey SSL certificates renewed for $DOMAIN" >> /var/log/valkey-ssl-renewal.log
