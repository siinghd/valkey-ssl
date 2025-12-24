#!/bin/bash
# Initialize Valkey Cluster with SSL

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Configuration
ANNOUNCE_IP="${ANNOUNCE_IP:-127.0.0.1}"
VALKEY_PASSWORD="${VALKEY_PASSWORD:-your-secure-password}"
NUM_NODES=6
BASE_PORT=6380
REPLICAS=1  # 1 replica per master = 3 masters + 3 replicas

echo "=== Initializing Valkey Cluster ==="
echo "Announce IP: $ANNOUNCE_IP"
echo "Configuration: 3 masters + 3 replicas"
echo ""

# Build node list
NODES=""
for i in $(seq 1 $NUM_NODES); do
    PORT=$((BASE_PORT + i - 1))
    NODES="$NODES $ANNOUNCE_IP:$PORT"
done

echo "Cluster nodes:$NODES"
echo ""

# Wait for all nodes to be ready
echo "Waiting for nodes to be ready..."
for i in $(seq 1 $NUM_NODES); do
    PORT=$((BASE_PORT + i - 1))
    until docker exec valkey-node-$i valkey-cli --tls --insecure -p $PORT -a "$VALKEY_PASSWORD" --no-auth-warning PING 2>/dev/null | grep -q PONG; do
        echo "  Waiting for node-$i (port $PORT)..."
        sleep 2
    done
    echo "  Node-$i ready"
done

echo ""
echo "Creating cluster..."

# Create cluster using the first node
docker exec valkey-node-1 valkey-cli --tls --insecure \
    -a "$VALKEY_PASSWORD" --no-auth-warning \
    --cluster create $NODES \
    --cluster-replicas $REPLICAS \
    --cluster-yes

echo ""
echo "=== Cluster Created ==="
echo ""

# Show cluster info
echo "Cluster nodes:"
docker exec valkey-node-1 valkey-cli --tls --insecure \
    -p 6380 -a "$VALKEY_PASSWORD" --no-auth-warning \
    CLUSTER NODES

echo ""
echo "Cluster info:"
docker exec valkey-node-1 valkey-cli --tls --insecure \
    -p 6380 -a "$VALKEY_PASSWORD" --no-auth-warning \
    CLUSTER INFO
