#!/bin/bash
# Valkey SSL - One Command Setup
#
# Usage:
#   ./setup.sh                      # Interactive setup
#   ./setup.sh --standalone         # Standalone instance
#   ./setup.sh --cluster            # 6-node cluster (single server)
#   ./setup.sh --multiserver-init   # Multi-server: initialize (run on first server)
#   ./setup.sh --multiserver-join   # Multi-server: join cluster (run on other servers)
#   ./setup.sh --password SECRET    # Use specific password

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Defaults
MODE=""
PASSWORD=""
DOMAIN="localhost"
NODE_ID=""
SERVER_IP=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --standalone) MODE="standalone"; shift ;;
        --cluster) MODE="cluster"; shift ;;
        --multiserver-init) MODE="multiserver-init"; shift ;;
        --multiserver-join) MODE="multiserver-join"; shift ;;
        --password) PASSWORD="$2"; shift 2 ;;
        --domain) DOMAIN="$2"; shift 2 ;;
        --node-id) NODE_ID="$2"; shift 2 ;;
        --ip) SERVER_IP="$2"; shift 2 ;;
        --help)
            echo "Usage: ./setup.sh [OPTIONS]"
            echo ""
            echo "Deployment modes:"
            echo "  --standalone         Single Valkey instance"
            echo "  --cluster            6-node cluster on single server (testing)"
            echo "  --multiserver-init   Multi-server cluster: run on FIRST server"
            echo "  --multiserver-join   Multi-server cluster: run on OTHER servers"
            echo ""
            echo "Options:"
            echo "  --password PASS      Use specific password (default: auto-generated)"
            echo "  --domain DOMAIN      Domain for certs (default: localhost)"
            echo "  --node-id ID         Node ID for multi-server (1-6)"
            echo "  --ip IP              This server's IP address"
            echo ""
            echo "Examples:"
            echo "  ./setup.sh --standalone"
            echo "  ./setup.sh --cluster --password mysecret"
            echo "  ./setup.sh --multiserver-init --password mysecret"
            echo "  ./setup.sh --multiserver-join --node-id 2 --ip 10.0.0.2 --password mysecret"
            echo ""
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# Generate password if not provided
if [ -z "$PASSWORD" ]; then
    PASSWORD=$(openssl rand -base64 32 | tr -d '/+=' | head -c 32)
fi

# Get server IP if not provided
if [ -z "$SERVER_IP" ]; then
    SERVER_IP=$(curl -4 -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
fi

echo -e "${GREEN}"
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║                    Valkey SSL Setup                           ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Interactive mode selection
if [ -z "$MODE" ]; then
    echo "Select deployment mode:"
    echo ""
    echo "  1) Standalone         - Single instance"
    echo "  2) Cluster            - 6 nodes on this server (testing)"
    echo "  3) Multi-Server Init  - First node of distributed cluster"
    echo "  4) Multi-Server Join  - Add this server to existing cluster"
    echo "  5) Exit"
    echo ""
    read -p "Enter choice [1-5]: " choice

    case $choice in
        1) MODE="standalone" ;;
        2) MODE="cluster" ;;
        3) MODE="multiserver-init" ;;
        4) MODE="multiserver-join" ;;
        5) exit 0 ;;
        *) echo "Invalid choice"; exit 1 ;;
    esac
fi

echo ""

# Ask for server address if standalone and not provided
if [ "$MODE" == "standalone" ] && [ "$DOMAIN" == "localhost" ]; then
    echo "How will clients connect to this server?"
    echo ""
    echo "  1) Domain name (e.g., redis.example.com) - for Let's Encrypt or custom certs"
    echo "  2) IP address only ($SERVER_IP) - self-signed certs"
    echo ""
    read -p "Enter choice [1-2]: " addr_choice

    case $addr_choice in
        1)
            read -p "Enter domain name: " user_domain
            if [ -n "$user_domain" ]; then
                DOMAIN="$user_domain"
            fi
            ;;
        2)
            DOMAIN="$SERVER_IP"
            ;;
    esac
    echo ""
fi

echo -e "${YELLOW}Mode: $MODE${NC}"
echo -e "${YELLOW}Server: ${DOMAIN:-$SERVER_IP}${NC}"
echo ""

# ============================================================================
# STANDALONE SETUP
# ============================================================================
if [ "$MODE" == "standalone" ]; then
    echo "Setting up standalone Valkey..."

    echo "1. Generating SSL certificates..."
    mkdir -p certs
    cd scripts && ./generate-certs.sh ../certs "$DOMAIN" 365 > /dev/null 2>&1 && cd ..

    echo "2. Creating configuration..."
    cp config/valkey.conf.example config/valkey.conf
    sed -i "s/your-secure-password-here/$PASSWORD/g" config/valkey.conf

    echo "VALKEY_PASSWORD=$PASSWORD" > .env

    echo "3. Starting Valkey..."
    docker compose up -d

    echo "4. Waiting for Valkey to be ready..."
    sleep 5

    if docker exec valkey-ssl valkey-cli --tls --insecure -a "$PASSWORD" --no-auth-warning PING | grep -q PONG; then
        echo ""
        echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
        echo -e "${GREEN}  Standalone Setup Complete!${NC}"
        echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
        echo ""
        echo -e "URL: ${CYAN}rediss://:$PASSWORD@$SERVER_IP:6379${NC}"
        echo ""
        echo "Test: docker exec valkey-ssl valkey-cli --tls --insecure -a '$PASSWORD' PING"
    else
        echo -e "${RED}Setup failed. Check: docker logs valkey-ssl${NC}"
        exit 1
    fi
fi

# ============================================================================
# SINGLE-SERVER CLUSTER
# ============================================================================
if [ "$MODE" == "cluster" ]; then
    echo "Setting up 6-node cluster on single server..."

    echo "1. Generating SSL certificates..."
    mkdir -p cluster/certs
    cd scripts && ./generate-certs.sh ../cluster/certs cluster.local 365 > /dev/null 2>&1 && cd ..

    echo "2. Generating cluster configurations..."
    cd cluster
    ANNOUNCE_IP="$SERVER_IP" VALKEY_PASSWORD="$PASSWORD" ./generate-cluster-config.sh > /dev/null 2>&1

    echo "3. Opening firewall ports..."
    sudo ufw allow 6380:6385/tcp > /dev/null 2>&1 || true

    echo "4. Starting cluster nodes..."
    docker compose up -d

    echo "5. Waiting for nodes..."
    sleep 10

    echo "6. Initializing cluster..."
    ANNOUNCE_IP="$SERVER_IP" VALKEY_PASSWORD="$PASSWORD" ./init-cluster.sh > /dev/null 2>&1
    cd ..

    sleep 3
    CLUSTER_STATE=$(docker exec valkey-node-1 valkey-cli --tls --insecure -p 6380 -a "$PASSWORD" --no-auth-warning CLUSTER INFO 2>/dev/null | grep cluster_state | cut -d: -f2 | tr -d '\r')

    if [ "$CLUSTER_STATE" == "ok" ]; then
        echo ""
        echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
        echo -e "${GREEN}  Cluster Setup Complete! (6 nodes)${NC}"
        echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
        echo ""
        echo -e "URLs: ${CYAN}rediss://:$PASSWORD@$SERVER_IP:6380${NC}"
        echo -e "      ${CYAN}rediss://:$PASSWORD@$SERVER_IP:6381${NC}"
        echo -e "      ${CYAN}rediss://:$PASSWORD@$SERVER_IP:6382${NC}"
        echo ""
        echo "Password: $PASSWORD"
    else
        echo -e "${RED}Cluster setup failed. Check: docker logs valkey-node-1${NC}"
        exit 1
    fi
fi

# ============================================================================
# MULTI-SERVER CLUSTER - INIT (First Server)
# ============================================================================
if [ "$MODE" == "multiserver-init" ]; then
    echo "Initializing multi-server cluster (Node 1)..."
    echo ""
    echo -e "${YELLOW}This server will be Node 1. Run --multiserver-join on other servers.${NC}"
    echo ""

    echo "1. Generating SSL certificates..."
    mkdir -p cluster/certs
    cd scripts && ./generate-certs.sh ../cluster/certs cluster.local 365 > /dev/null 2>&1 && cd ..

    echo "2. Creating cluster bundle for other servers..."
    cd cluster
    ./generate-multiserver-config.sh 1 "$SERVER_IP" "$PASSWORD" > /dev/null 2>&1

    # Create bundle for other servers
    BUNDLE_DIR="/tmp/valkey-cluster-bundle"
    rm -rf "$BUNDLE_DIR" && mkdir -p "$BUNDLE_DIR"
    cp -r certs "$BUNDLE_DIR/"
    echo "$PASSWORD" > "$BUNDLE_DIR/password.txt"
    echo "$SERVER_IP" > "$BUNDLE_DIR/node1-ip.txt"

    BUNDLE_FILE="$SCRIPT_DIR/cluster-bundle.tar.gz"
    tar -czf "$BUNDLE_FILE" -C "$BUNDLE_DIR" .
    rm -rf "$BUNDLE_DIR"

    echo "3. Opening firewall ports..."
    sudo ufw allow 6379/tcp > /dev/null 2>&1 || true
    sudo ufw allow 16379/tcp > /dev/null 2>&1 || true

    echo "4. Starting Node 1..."
    NODE_ID=1 docker compose -f docker-compose.multi-server.yml up -d

    cd ..

    sleep 5
    if docker exec valkey-node-1 valkey-cli --tls --insecure -p 6379 -a "$PASSWORD" --no-auth-warning PING | grep -q PONG; then
        echo ""
        echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
        echo -e "${GREEN}  Node 1 Ready! Now setup other servers.${NC}"
        echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
        echo ""
        echo -e "${CYAN}Step 1: Copy bundle to other servers:${NC}"
        echo "  scp $BUNDLE_FILE user@server2:/path/to/valkey-ssl/"
        echo "  scp $BUNDLE_FILE user@server3:/path/to/valkey-ssl/"
        echo "  ... (repeat for all 6 servers)"
        echo ""
        echo -e "${CYAN}Step 2: On each other server, run:${NC}"
        echo "  ./setup.sh --multiserver-join --node-id <2-6> --ip <server-ip>"
        echo ""
        echo -e "${CYAN}Step 3: After ALL 6 nodes are running, run on any server:${NC}"
        echo "  cd cluster && ./init-multiserver-cluster.sh '$PASSWORD' \\"
        echo "    $SERVER_IP:6379 <server2>:6379 <server3>:6379 \\"
        echo "    <server4>:6379 <server5>:6379 <server6>:6379"
        echo ""
        echo -e "Password: ${YELLOW}$PASSWORD${NC}"
        echo -e "Bundle: ${YELLOW}$BUNDLE_FILE${NC}"
    else
        echo -e "${RED}Node 1 failed to start. Check: docker logs valkey-node-1${NC}"
        exit 1
    fi
fi

# ============================================================================
# MULTI-SERVER CLUSTER - JOIN (Other Servers)
# ============================================================================
if [ "$MODE" == "multiserver-join" ]; then
    if [ -z "$NODE_ID" ]; then
        read -p "Enter Node ID for this server (2-6): " NODE_ID
    fi

    if [ "$NODE_ID" -lt 2 ] || [ "$NODE_ID" -gt 6 ]; then
        echo -e "${RED}Node ID must be 2-6 (Node 1 uses --multiserver-init)${NC}"
        exit 1
    fi

    BUNDLE_FILE="$SCRIPT_DIR/cluster-bundle.tar.gz"
    if [ ! -f "$BUNDLE_FILE" ]; then
        echo -e "${RED}Bundle not found: $BUNDLE_FILE${NC}"
        echo "Copy cluster-bundle.tar.gz from Node 1 server first."
        exit 1
    fi

    echo "Joining multi-server cluster as Node $NODE_ID..."

    echo "1. Extracting cluster bundle..."
    mkdir -p cluster/certs
    tar -xzf "$BUNDLE_FILE" -C cluster/

    # Read password from bundle
    if [ -f "cluster/password.txt" ]; then
        PASSWORD=$(cat cluster/password.txt)
        rm cluster/password.txt cluster/node1-ip.txt 2>/dev/null || true
    fi

    echo "2. Generating node configuration..."
    cd cluster
    ./generate-multiserver-config.sh "$NODE_ID" "$SERVER_IP" "$PASSWORD" > /dev/null 2>&1

    echo "3. Opening firewall ports..."
    sudo ufw allow 6379/tcp > /dev/null 2>&1 || true
    sudo ufw allow 16379/tcp > /dev/null 2>&1 || true

    echo "4. Starting Node $NODE_ID..."
    NODE_ID=$NODE_ID docker compose -f docker-compose.multi-server.yml up -d

    cd ..

    sleep 5
    if docker exec valkey-node-$NODE_ID valkey-cli --tls --insecure -p 6379 -a "$PASSWORD" --no-auth-warning PING | grep -q PONG; then
        echo ""
        echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
        echo -e "${GREEN}  Node $NODE_ID Ready!${NC}"
        echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
        echo ""
        echo "This node: $SERVER_IP:6379"
        echo ""
        echo "After ALL nodes are running, initialize cluster from any server:"
        echo "  cd cluster && ./init-multiserver-cluster.sh '$PASSWORD' <all-node-ips:6379>"
    else
        echo -e "${RED}Node $NODE_ID failed. Check: docker logs valkey-node-$NODE_ID${NC}"
        exit 1
    fi
fi

echo ""
echo -e "${GREEN}Done!${NC}"
