#!/bin/bash
# Valkey SSL - Teardown/Cleanup
#
# Usage:
#   ./teardown.sh              # Interactive
#   ./teardown.sh --all        # Remove everything
#   ./teardown.sh --standalone # Remove standalone only
#   ./teardown.sh --cluster    # Remove cluster only

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

MODE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --all) MODE="all"; shift ;;
        --standalone) MODE="standalone"; shift ;;
        --cluster) MODE="cluster"; shift ;;
        *) shift ;;
    esac
done

if [ -z "$MODE" ]; then
    echo "What do you want to remove?"
    echo ""
    echo "  1) Standalone only"
    echo "  2) Cluster only"
    echo "  3) Everything (standalone + cluster + data)"
    echo "  4) Cancel"
    echo ""
    read -p "Enter choice [1-4]: " choice

    case $choice in
        1) MODE="standalone" ;;
        2) MODE="cluster" ;;
        3) MODE="all" ;;
        4) exit 0 ;;
        *) echo "Invalid choice"; exit 1 ;;
    esac
fi

echo ""

if [ "$MODE" == "standalone" ] || [ "$MODE" == "all" ]; then
    echo -e "${YELLOW}Removing standalone...${NC}"
    docker compose down 2>/dev/null || true
    if [ "$MODE" == "all" ]; then
        sudo rm -rf data certs .env config/valkey.conf 2>/dev/null || true
    fi
fi

if [ "$MODE" == "cluster" ] || [ "$MODE" == "all" ]; then
    echo -e "${YELLOW}Removing cluster...${NC}"
    cd cluster
    docker compose down 2>/dev/null || true
    if [ "$MODE" == "all" ]; then
        sudo rm -rf data certs config 2>/dev/null || true
    fi
    cd ..
fi

echo ""
echo -e "${GREEN}Cleanup complete!${NC}"
