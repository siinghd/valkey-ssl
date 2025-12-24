#!/bin/bash
# Generate Valkey config for multi-server cluster deployment
# Run this on EACH server with appropriate parameters
#
# Usage:
#   ./generate-multiserver-config.sh <NODE_ID> <ANNOUNCE_IP> <PASSWORD>
#
# Example (6 servers, 3 masters + 3 replicas):
#   Server 1: ./generate-multiserver-config.sh 1 10.0.0.1 mysecretpass
#   Server 2: ./generate-multiserver-config.sh 2 10.0.0.2 mysecretpass
#   Server 3: ./generate-multiserver-config.sh 3 10.0.0.3 mysecretpass
#   Server 4: ./generate-multiserver-config.sh 4 10.0.0.4 mysecretpass
#   Server 5: ./generate-multiserver-config.sh 5 10.0.0.5 mysecretpass
#   Server 6: ./generate-multiserver-config.sh 6 10.0.0.6 mysecretpass

set -e

NODE_ID="${1:?Usage: $0 <NODE_ID> <ANNOUNCE_IP> <PASSWORD>}"
ANNOUNCE_IP="${2:?Usage: $0 <NODE_ID> <ANNOUNCE_IP> <PASSWORD>}"
VALKEY_PASSWORD="${3:?Usage: $0 <NODE_ID> <ANNOUNCE_IP> <PASSWORD>}"
NODE_PORT="${NODE_PORT:-6379}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/config"
DATA_DIR="$SCRIPT_DIR/data"

echo "=== Generating Multi-Server Cluster Config ==="
echo "Node ID: $NODE_ID"
echo "Announce IP: $ANNOUNCE_IP"
echo "Port: $NODE_PORT"
echo ""

mkdir -p "$CONFIG_DIR" "$DATA_DIR"

cat > "$CONFIG_DIR/node-$NODE_ID.conf" << EOF
# Valkey Cluster Node $NODE_ID - Multi-Server Configuration
# Generated for: $ANNOUNCE_IP:$NODE_PORT

# =============================================================================
# NETWORK
# =============================================================================
bind 0.0.0.0
port 0
tls-port $NODE_PORT
protected-mode yes

# =============================================================================
# CLUSTER
# =============================================================================
cluster-enabled yes
cluster-config-file nodes-$NODE_ID.conf
cluster-node-timeout 5000
cluster-announce-ip $ANNOUNCE_IP
cluster-announce-port $NODE_PORT
cluster-announce-tls-port $NODE_PORT
cluster-announce-bus-port $((NODE_PORT + 10000))
cluster-require-full-coverage yes
cluster-replica-validity-factor 10

# =============================================================================
# TLS/SSL
# =============================================================================
tls-cert-file /certs/valkey.crt
tls-key-file /certs/valkey.key
tls-ca-cert-file /certs/ca.crt
tls-cluster yes
tls-replication yes
tls-protocols "TLSv1.2 TLSv1.3"
tls-ciphersuites TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256:TLS_AES_128_GCM_SHA256
tls-prefer-server-ciphers yes
tls-auth-clients optional
tls-session-caching yes
tls-session-cache-size 20480
tls-session-cache-timeout 300

# =============================================================================
# AUTHENTICATION
# =============================================================================
requirepass $VALKEY_PASSWORD
masterauth $VALKEY_PASSWORD

# =============================================================================
# MEMORY
# =============================================================================
maxmemory 1gb
maxmemory-policy allkeys-lru
lazyfree-lazy-eviction yes
lazyfree-lazy-expire yes
lazyfree-lazy-server-del yes
lazyfree-lazy-user-del yes
replica-lazy-flush yes
activedefrag yes

# =============================================================================
# PERSISTENCE
# =============================================================================
save 900 1
save 300 10
save 60 10000
dbfilename dump.rdb
dir /data
rdbcompression yes
appendonly yes
appendfilename "appendonly.aof"
appendfsync everysec
aof-use-rdb-preamble yes

# =============================================================================
# PERFORMANCE
# =============================================================================
tcp-backlog 4096
tcp-keepalive 300
timeout 0
maxclients 10000

# =============================================================================
# LOGGING
# =============================================================================
loglevel notice
logfile ""
slowlog-log-slower-than 10000
slowlog-max-len 128
latency-monitor-threshold 100
EOF

chmod 644 "$CONFIG_DIR/node-$NODE_ID.conf"

echo "Config created: $CONFIG_DIR/node-$NODE_ID.conf"
echo ""
echo "=== Next Steps ==="
echo ""
echo "1. Copy certs to this server:"
echo "   scp -r user@cert-server:/path/to/cluster/certs $SCRIPT_DIR/"
echo ""
echo "2. Open firewall ports:"
echo "   sudo ufw allow $NODE_PORT/tcp comment 'Valkey'"
echo "   sudo ufw allow $((NODE_PORT + 10000))/tcp comment 'Valkey Cluster Bus'"
echo ""
echo "3. Start this node:"
echo "   NODE_ID=$NODE_ID docker compose -f docker-compose.multi-server.yml up -d"
echo ""
echo "4. After ALL nodes are running, initialize cluster from any node:"
echo "   ./init-multiserver-cluster.sh"
