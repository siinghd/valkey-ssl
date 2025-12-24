#!/bin/bash
# Test Valkey SSL connection

CERTS_DIR="${1:-../certs}"
HOST="${2:-localhost}"
PORT="${3:-6379}"
PASSWORD="${4:-}"

echo "=== Testing Valkey SSL Connection ==="
echo "Host: $HOST:$PORT"
echo ""

# Test with valkey-cli or redis-cli (compatible)
CLI_CMD=""
if command -v valkey-cli &> /dev/null; then
    CLI_CMD="valkey-cli"
elif command -v redis-cli &> /dev/null; then
    CLI_CMD="redis-cli"
fi

if [ -n "$CLI_CMD" ]; then
    echo "Using $CLI_CMD..."
    $CLI_CMD --tls \
        --cert "$CERTS_DIR/client.crt" \
        --key "$CERTS_DIR/client.key" \
        --cacert "$CERTS_DIR/ca.crt" \
        -h "$HOST" \
        -p "$PORT" \
        -a "$PASSWORD" \
        --no-auth-warning \
        PING
else
    echo "No CLI found. Using openssl to test SSL handshake..."
    echo -e "AUTH $PASSWORD\r\nPING\r\n" | timeout 5 openssl s_client -connect "$HOST:$PORT" \
        -cert "$CERTS_DIR/client.crt" \
        -key "$CERTS_DIR/client.key" \
        -CAfile "$CERTS_DIR/ca.crt" \
        -quiet 2>/dev/null
fi

echo ""
echo "=== Connection Test Complete ==="
