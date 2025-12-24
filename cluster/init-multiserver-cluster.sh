#!/bin/bash
# Initialize Valkey Cluster across multiple servers
#
# Usage:
#   ./init-multiserver-cluster.sh <password> <server1:port> <server2:port> ...
#
# Example (6 nodes = 3 masters + 3 replicas):
#   ./init-multiserver-cluster.sh mysecretpass \
#     10.0.0.1:6379 10.0.0.2:6379 10.0.0.3:6379 \
#     10.0.0.4:6379 10.0.0.5:6379 10.0.0.6:6379
#
# Minimum: 6 nodes for 3 masters + 3 replicas
# Or: 3 nodes for 3 masters (no HA)

set -e

VALKEY_PASSWORD="${1:?Usage: $0 <password> <server1:port> <server2:port> ...}"
shift
NODES="$@"

if [ -z "$NODES" ]; then
    echo "Error: No nodes specified"
    echo "Usage: $0 <password> <server1:port> <server2:port> ..."
    exit 1
fi

NODE_COUNT=$(echo "$NODES" | wc -w)

if [ "$NODE_COUNT" -lt 3 ]; then
    echo "Error: Minimum 3 nodes required for cluster"
    exit 1
fi

# Determine replicas
if [ "$NODE_COUNT" -ge 6 ]; then
    REPLICAS=1
    echo "Mode: 3 masters + 3 replicas (HA enabled)"
elif [ "$NODE_COUNT" -ge 3 ]; then
    REPLICAS=0
    echo "Mode: $NODE_COUNT masters, no replicas (no HA)"
    echo "WARNING: Add more nodes for high availability"
fi

echo ""
echo "=== Initializing Multi-Server Valkey Cluster ==="
echo "Nodes: $NODES"
echo "Replicas per master: $REPLICAS"
echo ""

# Test connectivity to all nodes
echo "Testing connectivity..."
for NODE in $NODES; do
    HOST=$(echo $NODE | cut -d: -f1)
    PORT=$(echo $NODE | cut -d: -f2)

    if timeout 5 bash -c "echo PING | openssl s_client -connect $HOST:$PORT -quiet 2>/dev/null" | grep -q PONG 2>/dev/null; then
        echo "  ✓ $NODE - reachable (no auth test)"
    else
        # Try with valkey-cli if available
        if command -v valkey-cli &> /dev/null; then
            if valkey-cli --tls --insecure -h $HOST -p $PORT -a "$VALKEY_PASSWORD" --no-auth-warning PING 2>/dev/null | grep -q PONG; then
                echo "  ✓ $NODE - reachable"
            else
                echo "  ✗ $NODE - FAILED"
                echo "    Check: firewall, TLS certs, password"
                exit 1
            fi
        else
            echo "  ? $NODE - cannot verify (install valkey-cli)"
        fi
    fi
done

echo ""
echo "Creating cluster..."

# Use valkey-cli to create cluster
if command -v valkey-cli &> /dev/null; then
    valkey-cli --tls --insecure \
        -a "$VALKEY_PASSWORD" --no-auth-warning \
        --cluster create $NODES \
        --cluster-replicas $REPLICAS \
        --cluster-yes
else
    # Try using docker on first node
    FIRST_NODE=$(echo $NODES | awk '{print $1}')
    FIRST_HOST=$(echo $FIRST_NODE | cut -d: -f1)
    FIRST_PORT=$(echo $FIRST_NODE | cut -d: -f2)

    echo "valkey-cli not found locally, trying via docker..."
    docker run --rm --network host valkey/valkey:8-alpine \
        valkey-cli --tls --insecure \
        -a "$VALKEY_PASSWORD" --no-auth-warning \
        --cluster create $NODES \
        --cluster-replicas $REPLICAS \
        --cluster-yes
fi

echo ""
echo "=== Cluster Created ==="
echo ""
echo "Verify with:"
echo "  valkey-cli --tls --insecure -h <any-node-ip> -p 6379 -a '$VALKEY_PASSWORD' CLUSTER INFO"
