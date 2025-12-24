#!/bin/bash
# Generate Valkey + Sentinel configuration for multi-server HA
#
# Usage:
#   ./generate-sentinel-config.sh <ROLE> <THIS_IP> <MASTER_IP> <PASSWORD>
#
# ROLE: master, replica
#
# Example (3-server setup):
#   Server 1 (master):  ./generate-sentinel-config.sh master  10.0.0.1 10.0.0.1 mysecret
#   Server 2 (replica): ./generate-sentinel-config.sh replica 10.0.0.2 10.0.0.1 mysecret
#   Server 3 (replica): ./generate-sentinel-config.sh replica 10.0.0.3 10.0.0.1 mysecret

set -e

ROLE="${1:?Usage: $0 <master|replica> <THIS_IP> <MASTER_IP> <PASSWORD>}"
THIS_IP="${2:?Usage: $0 <master|replica> <THIS_IP> <MASTER_IP> <PASSWORD>}"
MASTER_IP="${3:?Usage: $0 <master|replica> <THIS_IP> <MASTER_IP> <PASSWORD>}"
VALKEY_PASSWORD="${4:?Usage: $0 <master|replica> <THIS_IP> <MASTER_IP> <PASSWORD>}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/config"
DATA_DIR="$SCRIPT_DIR/data"

echo "=== Generating Sentinel HA Config ==="
echo "Role: $ROLE"
echo "This server: $THIS_IP"
echo "Master: $MASTER_IP"
echo ""

mkdir -p "$CONFIG_DIR" "$DATA_DIR"

# Generate Valkey config
cat > "$CONFIG_DIR/valkey.conf" << EOF
# Valkey Configuration - $ROLE
# Server: $THIS_IP

# =============================================================================
# NETWORK
# =============================================================================
bind 0.0.0.0
port 0
tls-port 6379
protected-mode yes

# =============================================================================
# TLS/SSL
# =============================================================================
tls-cert-file /certs/valkey.crt
tls-key-file /certs/valkey.key
tls-ca-cert-file /certs/ca.crt
tls-replication yes
tls-protocols "TLSv1.2 TLSv1.3"
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
# REPLICATION
# =============================================================================
EOF

if [ "$ROLE" == "replica" ]; then
    cat >> "$CONFIG_DIR/valkey.conf" << EOF
replicaof $MASTER_IP 6379
replica-announce-ip $THIS_IP
replica-announce-port 6379
EOF
else
    echo "# This is the master" >> "$CONFIG_DIR/valkey.conf"
fi

cat >> "$CONFIG_DIR/valkey.conf" << EOF

# =============================================================================
# MEMORY
# =============================================================================
maxmemory 2gb
maxmemory-policy allkeys-lru
lazyfree-lazy-eviction yes
lazyfree-lazy-expire yes
lazyfree-lazy-server-del yes

# =============================================================================
# PERSISTENCE
# =============================================================================
save 900 1
save 300 10
save 60 10000
dbfilename dump.rdb
dir /data
appendonly yes
appendfilename "appendonly.aof"
appendfsync everysec

# =============================================================================
# PERFORMANCE
# =============================================================================
tcp-backlog 4096
tcp-keepalive 300
timeout 0
EOF

# Generate Sentinel config
cat > "$CONFIG_DIR/sentinel.conf" << EOF
# Valkey Sentinel Configuration
# Server: $THIS_IP

# =============================================================================
# NETWORK
# =============================================================================
port 0
tls-port 26379
bind 0.0.0.0

# =============================================================================
# TLS/SSL
# =============================================================================
tls-cert-file /certs/valkey.crt
tls-key-file /certs/valkey.key
tls-ca-cert-file /certs/ca.crt
tls-replication yes
tls-protocols "TLSv1.2 TLSv1.3"
tls-prefer-server-ciphers yes
tls-auth-clients optional

# =============================================================================
# SENTINEL MONITORING
# =============================================================================
# Monitor master - quorum of 2 (majority of 3 sentinels)
sentinel monitor mymaster $MASTER_IP 6379 2

# Authentication
sentinel auth-pass mymaster $VALKEY_PASSWORD

# Use TLS for master connection
sentinel master-reboot-down-after-period mymaster 0

# =============================================================================
# TIMEOUTS
# =============================================================================
# Consider master down after 5 seconds
sentinel down-after-milliseconds mymaster 5000

# Failover timeout: 60 seconds
sentinel failover-timeout mymaster 60000

# Only sync 1 replica at a time during failover
sentinel parallel-syncs mymaster 1

# =============================================================================
# ANNOUNCE
# =============================================================================
sentinel announce-ip $THIS_IP
sentinel announce-port 26379

# Resolve hostnames (for domain support)
sentinel resolve-hostnames yes
sentinel announce-hostnames yes
EOF

chmod 644 "$CONFIG_DIR/valkey.conf" "$CONFIG_DIR/sentinel.conf"

echo "Created: $CONFIG_DIR/valkey.conf"
echo "Created: $CONFIG_DIR/sentinel.conf"
echo ""
echo "=== Next Steps ==="
echo ""
echo "1. Copy certs to this server (if not already done):"
echo "   scp -r user@cert-server:/path/to/sentinel/certs $SCRIPT_DIR/"
echo ""
echo "2. Open firewall ports:"
echo "   sudo ufw allow 6379/tcp   # Valkey"
echo "   sudo ufw allow 26379/tcp  # Sentinel"
echo ""
echo "3. Start services:"
echo "   docker compose up -d"
echo ""
if [ "$ROLE" == "master" ]; then
    echo "4. After ALL servers are running, verify with:"
    echo "   docker exec valkey-sentinel valkey-cli --tls --insecure -p 26379 SENTINEL masters"
fi
