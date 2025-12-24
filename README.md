# Valkey SSL

Production-ready Valkey deployment with TLS/SSL encryption. Supports standalone and cluster modes.

[Valkey](https://valkey.io/) is an open source (BSD-3 licensed), high-performance key/value datastore - a community-driven fork of Redis.

## Features

- TLS 1.2/1.3 encryption for all connections
- Self-signed certificates or Let's Encrypt support
- Docker Compose deployment
- Standalone and 6-node cluster modes
- Automatic certificate renewal
- Production-ready configuration

## Quick Start (One Command)

```bash
git clone https://github.com/hsingh/valkey-ssl.git
cd valkey-ssl
./setup.sh
```

That's it! The setup script will:
- Generate a secure random password
- Create SSL certificates
- Configure and start Valkey
- Display connection URL

### Options

```bash
./setup.sh --standalone     # Single instance (default)
./setup.sh --cluster        # 6-node cluster
./setup.sh --password PASS  # Use specific password
```

### Teardown

```bash
./teardown.sh              # Interactive cleanup
./teardown.sh --all        # Remove everything
```

---

## Manual Setup

If you prefer manual control:

### 1. Generate Certificates

**Option A: Self-signed (for testing/internal use)**
```bash
cd scripts
./generate-certs.sh ../certs your-domain.com 365
```

**Option B: Let's Encrypt (for production)**
```bash
# Point DNS to your server first (A record, no proxy)
sudo certbot certonly --webroot -w /var/www/html -d your-domain.com

# Copy certs
sudo cp /etc/letsencrypt/live/your-domain.com/fullchain.pem certs/valkey.crt
sudo cp /etc/letsencrypt/live/your-domain.com/privkey.pem certs/valkey.key
chmod 644 certs/valkey.*
```

### 3. Start Valkey

```bash
docker compose up -d
```

### 4. Test Connection

```bash
# Using docker
docker exec valkey-ssl valkey-cli --tls --insecure -a your-password PING

# Using redis-cli (Let's Encrypt)
redis-cli --tls -h your-domain.com -a your-password PING

# Using redis-cli (self-signed)
redis-cli --tls --cacert certs/ca.crt -h your-domain.com -a your-password PING
```

## Connection URL

```
rediss://:your-password@your-domain.com:6379
```

## Cluster Mode

For high availability with automatic sharding (3 masters + 3 replicas):

### Setup Cluster

```bash
cd cluster

# Generate self-signed certs for cluster
cd ../scripts
./generate-certs.sh ../cluster/certs cluster.local 365
cd ../cluster

# Generate node configs
ANNOUNCE_IP=your-server-ip VALKEY_PASSWORD=your-password ./generate-cluster-config.sh

# Start cluster
docker compose up -d

# Initialize cluster
ANNOUNCE_IP=your-server-ip VALKEY_PASSWORD=your-password ./init-cluster.sh
```

### Cluster Ports

| Node | Port | Role |
|------|------|------|
| 1 | 6380 | Master |
| 2 | 6381 | Master |
| 3 | 6382 | Master |
| 4 | 6383 | Replica |
| 5 | 6384 | Replica |
| 6 | 6385 | Replica |

### Cluster Connection

```bash
# CLI (use -c for cluster mode)
redis-cli --tls --insecure -c -h your-server-ip -p 6380 -a your-password

# Connection URLs (any node works)
rediss://:your-password@your-server-ip:6380
rediss://:your-password@your-server-ip:6381
rediss://:your-password@your-server-ip:6382
```

## Client Examples

### Node.js (ioredis)

**Standalone:**
```javascript
const Redis = require('ioredis');
const redis = new Redis({
  host: 'your-domain.com',
  port: 6379,
  password: 'your-password',
  tls: {}
});
```

**Cluster:**
```javascript
const Redis = require('ioredis');
const cluster = new Redis.Cluster([
  { host: 'your-server-ip', port: 6380 },
  { host: 'your-server-ip', port: 6381 },
  { host: 'your-server-ip', port: 6382 }
], {
  redisOptions: {
    password: 'your-password',
    tls: {}
  }
});
```

### Python (redis-py)

**Standalone:**
```python
import redis
r = redis.Redis(
    host='your-domain.com',
    port=6379,
    password='your-password',
    ssl=True
)
```

**Cluster:**
```python
from redis.cluster import RedisCluster
rc = RedisCluster(
    host='your-server-ip',
    port=6380,
    password='your-password',
    ssl=True
)
```

## Configuration

### Standalone (`config/valkey.conf`)

| Setting | Default | Description |
|---------|---------|-------------|
| `tls-port` | 6379 | TLS listening port |
| `maxmemory` | 2gb | Maximum memory usage |
| `requirepass` | - | Authentication password |
| `appendonly` | yes | Enable AOF persistence |

### Security

Dangerous commands are disabled by default:
- `FLUSHDB`, `FLUSHALL`, `DEBUG` - disabled
- `CONFIG` - renamed to `CONFIG_a8f3b2c1`

## Let's Encrypt Auto-Renewal

To automatically update Valkey certs when Let's Encrypt renews:

```bash
# Edit the renewal script with your values
nano scripts/renew-certs.sh

# Link to certbot hooks
sudo ln -sf $(pwd)/scripts/renew-certs.sh /etc/letsencrypt/renewal-hooks/deploy/valkey-ssl.sh
```

## Scalability & Production

### Host Optimization

Run on each server for optimal performance:
```bash
sudo ./scripts/optimize-host.sh
```

This configures:
- Disables Transparent Huge Pages (reduces latency spikes)
- Sets `vm.overcommit_memory=1` (prevents background save failures)
- Increases TCP backlog and file descriptors
- Optimizes TCP keepalive settings

### Automated Backups

```bash
# Manual backup
VALKEY_PASSWORD=your-password ./scripts/backup.sh /backups

# Cron (every 6 hours)
0 */6 * * * VALKEY_PASSWORD=your-password /path/to/backup.sh /backups
```

### Monitoring

Start Prometheus exporter:
```bash
cd monitoring
VALKEY_PASSWORD=your-password docker compose up -d
```

Metrics available at `http://localhost:9121/metrics`

### Multi-Server Cluster

For true HA, deploy across 6 servers (3 masters + 3 replicas):

**Step 1: Generate certs (once, on any server)**
```bash
cd cluster
../scripts/generate-certs.sh ./certs cluster.local 365
```

**Step 2: On EACH server**
```bash
# Copy the repo
git clone https://github.com/hsingh/valkey-ssl.git
cd valkey-ssl/cluster

# Copy certs from step 1
scp -r user@cert-server:/path/to/cluster/certs ./

# Generate config for this node
./generate-multiserver-config.sh <NODE_ID> <THIS_SERVER_IP> <PASSWORD>
# Example: ./generate-multiserver-config.sh 1 10.0.0.1 mysecretpass

# Open firewall (port + cluster bus port)
sudo ufw allow 6379/tcp
sudo ufw allow 16379/tcp

# Start node
NODE_ID=1 docker compose -f docker-compose.multi-server.yml up -d
```

**Step 3: Initialize cluster (from any server, after ALL nodes running)**
```bash
./init-multiserver-cluster.sh <PASSWORD> \
  10.0.0.1:6379 10.0.0.2:6379 10.0.0.3:6379 \
  10.0.0.4:6379 10.0.0.5:6379 10.0.0.6:6379
```

### Sentinel (Alternative to Cluster)

For automatic failover without sharding:
```bash
cd sentinel
# Configure sentinel.conf with your master IP
docker compose up -d
```

## File Structure

```
valkey-ssl/
├── setup.sh                        # One-command setup
├── teardown.sh                     # Cleanup script
├── docker-compose.yml              # Standalone deployment
├── .env.example                    # Environment template
├── config/
│   └── valkey.conf.example         # Config template (optimized)
├── certs/                          # SSL certificates
├── data/                           # Persistent data
├── scripts/
│   ├── generate-certs.sh           # Self-signed cert generator
│   ├── renew-certs.sh              # Let's Encrypt renewal
│   ├── backup.sh                   # Automated backups
│   ├── optimize-host.sh            # OS/kernel tuning
│   └── test-connection.sh          # Connection tester
├── cluster/
│   ├── docker-compose.yml              # Single-server cluster (testing)
│   ├── docker-compose.multi-server.yml # Multi-server cluster (production)
│   ├── generate-cluster-config.sh      # Single-server config generator
│   ├── generate-multiserver-config.sh  # Multi-server config generator
│   ├── init-cluster.sh                 # Single-server init
│   ├── init-multiserver-cluster.sh     # Multi-server init
│   └── valkey-cluster.conf.template
├── sentinel/
│   ├── docker-compose.yml          # Sentinel HA
│   └── sentinel.conf.template
└── monitoring/
    ├── docker-compose.yml          # Prometheus exporter
    └── prometheus.yml              # Prometheus config
```

## License

BSD-3-Clause (same as Valkey)
