#!/bin/bash
# Valkey Backup Script
# Creates RDB snapshot and copies to backup location
#
# Usage: ./backup.sh [backup_dir]
# Cron:  0 */6 * * * /path/to/backup.sh /backups/valkey

set -e

BACKUP_DIR="${1:-./backups}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
VALKEY_PASSWORD="${VALKEY_PASSWORD:-your-password}"
VALKEY_PORT="${VALKEY_PORT:-6379}"
RETENTION_DAYS="${RETENTION_DAYS:-7}"

mkdir -p "$BACKUP_DIR"

echo "=== Valkey Backup - $TIMESTAMP ==="

# Trigger BGSAVE
echo "Triggering background save..."
docker exec valkey-ssl valkey-cli --tls --insecure -p $VALKEY_PORT -a "$VALKEY_PASSWORD" --no-auth-warning BGSAVE

# Wait for save to complete
echo "Waiting for save to complete..."
while [ "$(docker exec valkey-ssl valkey-cli --tls --insecure -p $VALKEY_PORT -a "$VALKEY_PASSWORD" --no-auth-warning LASTSAVE)" == "$(docker exec valkey-ssl valkey-cli --tls --insecure -p $VALKEY_PORT -a "$VALKEY_PASSWORD" --no-auth-warning LASTSAVE)" ]; do
    sleep 1
done

# Copy RDB file
echo "Copying RDB file..."
docker cp valkey-ssl:/data/dump.rdb "$BACKUP_DIR/dump_$TIMESTAMP.rdb"

# Compress
echo "Compressing..."
gzip "$BACKUP_DIR/dump_$TIMESTAMP.rdb"

# Cleanup old backups
echo "Cleaning up backups older than $RETENTION_DAYS days..."
find "$BACKUP_DIR" -name "dump_*.rdb.gz" -mtime +$RETENTION_DAYS -delete

# Show backup size
BACKUP_SIZE=$(ls -lh "$BACKUP_DIR/dump_$TIMESTAMP.rdb.gz" | awk '{print $5}')
echo ""
echo "=== Backup Complete ==="
echo "File: $BACKUP_DIR/dump_$TIMESTAMP.rdb.gz"
echo "Size: $BACKUP_SIZE"
