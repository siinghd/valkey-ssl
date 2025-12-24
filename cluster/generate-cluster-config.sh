#!/bin/bash
# Generate Valkey Cluster node configurations

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/config"
DATA_DIR="$SCRIPT_DIR/data"
TEMPLATE="$SCRIPT_DIR/valkey-cluster.conf.template"

# Configuration
ANNOUNCE_IP="${ANNOUNCE_IP:-127.0.0.1}"
VALKEY_PASSWORD="${VALKEY_PASSWORD:-your-secure-password}"
NUM_NODES=6
BASE_PORT=6380

echo "=== Generating Valkey Cluster Configurations ==="
echo "Announce IP: $ANNOUNCE_IP"
echo "Nodes: $NUM_NODES"
echo "Ports: $BASE_PORT - $((BASE_PORT + NUM_NODES - 1))"
echo ""

# Create directories
mkdir -p "$CONFIG_DIR"
for i in $(seq 1 $NUM_NODES); do
    mkdir -p "$DATA_DIR/node-$i"
done

# Generate node configs
for i in $(seq 1 $NUM_NODES); do
    PORT=$((BASE_PORT + i - 1))
    CONFIG_FILE="$CONFIG_DIR/node-$i.conf"

    echo "Generating node-$i config (port $PORT)..."

    sed -e "s/{{NODE_PORT}}/$PORT/g" \
        -e "s/{{NODE_ID}}/$i/g" \
        -e "s/{{ANNOUNCE_IP}}/$ANNOUNCE_IP/g" \
        -e "s/{{VALKEY_PASSWORD}}/$VALKEY_PASSWORD/g" \
        "$TEMPLATE" > "$CONFIG_FILE"

    chmod 644 "$CONFIG_FILE"
done

echo ""
echo "=== Configuration Generated ==="
echo ""
echo "Files created:"
ls -la "$CONFIG_DIR"
echo ""
echo "Next steps:"
echo "  1. Update ANNOUNCE_IP if needed (current: $ANNOUNCE_IP)"
echo "  2. Start cluster: docker compose up -d"
echo "  3. Initialize cluster: ./init-cluster.sh"
