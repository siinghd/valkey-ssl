# Valkey SSL

Production-ready Valkey deployment with TLS/SSL encryption. Supports standalone and cluster modes.

[Valkey](https://valkey.io/) is an open source (BSD-3 licensed), high-performance key/value datastore - a community-driven fork of Redis.

## Features

- TLS 1.2/1.3 encryption for all connections
- Self-signed certificates or Let's Encrypt support
- Docker Compose deployment
- Standalone and 6-node cluster modes
- Multi-server distributed cluster support
- Automatic certificate renewal
- Production-ready configuration

## Quick Start (One Command)

```bash
git clone https://github.com/siinghd/valkey-ssl.git
cd valkey-ssl
./setup.sh
```

The interactive setup will guide you through:
- Selecting deployment mode (standalone, cluster, multi-server)
- Choosing IP or domain name
- Generating secure password and certificates
- Starting Valkey

### CLI Options

```bash
./setup.sh --standalone                    # Single instance
./setup.sh --standalone --domain redis.example.com  # With domain
./setup.sh --cluster                       # 6-node cluster (single server)
./setup.sh --cluster --password SECRET     # With specific password

# Multi-server cluster
./setup.sh --multiserver-init --address 10.0.0.1
./setup.sh --multiserver-init --address redis1.example.com
./setup.sh --multiserver-join --node-id 2 --address redis2.example.com
```

### Teardown

```bash
./teardown.sh              # Interactive cleanup
./teardown.sh --all        # Remove everything
```

---

## Multi-Server Cluster (Production HA)

Deploy across 6 servers for true high availability (3 masters + 3 replicas).

### Using setup.sh (Recommended)

**Server 1 (Node 1):**
```bash
./setup.sh --multiserver-init --password mysecret --address 10.0.0.1
# Or with domain:
./setup.sh --multiserver-init --password mysecret --address redis1.example.com
```

This creates `cluster-bundle.tar.gz` containing certs and password.

**Copy bundle to other servers:**
```bash
scp cluster-bundle.tar.gz user@server2:/path/to/valkey-ssl/
scp cluster-bundle.tar.gz user@server3:/path/to/valkey-ssl/
# ... repeat for all servers
```

**Servers 2-6:**
```bash
./setup.sh --multiserver-join --node-id 2 --address 10.0.0.2
./setup.sh --multiserver-join --node-id 3 --address 10.0.0.3
# ... etc
```

**Initialize cluster (after ALL nodes running):**
```bash
cd cluster
./init-multiserver-cluster.sh 'mysecret' \
  10.0.0.1:6379 10.0.0.2:6379 10.0.0.3:6379 \
  10.0.0.4:6379 10.0.0.5:6379 10.0.0.6:6379
```

### Manual Multi-Server Setup

**Step 1: Generate certs (once, on any server)**
```bash
cd cluster
../scripts/generate-certs.sh ./certs cluster.local 365
```

**Step 2: On EACH server**
```bash
git clone https://github.com/siinghd/valkey-ssl.git
cd valkey-ssl/cluster

# Copy certs from step 1
scp -r user@cert-server:/path/to/cluster/certs ./

# Generate config (use IP or domain)
./generate-multiserver-config.sh 1 10.0.0.1 mysecretpass
# Or: ./generate-multiserver-config.sh 1 redis1.example.com mysecretpass

# Open firewall
sudo ufw allow 6379/tcp
sudo ufw allow 16379/tcp

# Start node
NODE_ID=1 docker compose -f docker-compose.multi-server.yml up -d
```

**Step 3: Initialize cluster**
```bash
./init-multiserver-cluster.sh mysecretpass \
  10.0.0.1:6379 10.0.0.2:6379 10.0.0.3:6379 \
  10.0.0.4:6379 10.0.0.5:6379 10.0.0.6:6379
```

---

## Single-Server Cluster (Testing)

For testing cluster mode on a single server (6 nodes on ports 6380-6385):

```bash
./setup.sh --cluster
```

Or manually:
```bash
cd cluster
ANNOUNCE_IP=your-server-ip VALKEY_PASSWORD=your-password ./generate-cluster-config.sh
docker compose up -d
ANNOUNCE_IP=your-server-ip VALKEY_PASSWORD=your-password ./init-cluster.sh
```

| Node | Port | Role |
|------|------|------|
| 1 | 6380 | Master |
| 2 | 6381 | Master |
| 3 | 6382 | Master |
| 4 | 6383 | Replica |
| 5 | 6384 | Replica |
| 6 | 6385 | Replica |

---

## Manual Standalone Setup

### 1. Generate Certificates

**Self-signed (testing/internal):**
```bash
cd scripts
./generate-certs.sh ../certs your-domain.com 365
```

**Let's Encrypt (production):**
```bash
sudo certbot certonly --webroot -w /var/www/html -d your-domain.com
sudo cp /etc/letsencrypt/live/your-domain.com/fullchain.pem certs/valkey.crt
sudo cp /etc/letsencrypt/live/your-domain.com/privkey.pem certs/valkey.key
chmod 644 certs/valkey.*
```

### 2. Configure and Start

```bash
cp config/valkey.conf.example config/valkey.conf
# Edit config/valkey.conf to set password
docker compose up -d
```

### 3. Test Connection

```bash
docker exec valkey-ssl valkey-cli --tls --insecure -a your-password PING
```

## Connection URL

```
rediss://:your-password@your-domain.com:6379
```

---

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
  { host: 'redis1.example.com', port: 6379 },
  { host: 'redis2.example.com', port: 6379 },
  { host: 'redis3.example.com', port: 6379 }
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
    host='redis1.example.com',
    port=6379,
    password='your-password',
    ssl=True
)
```

---

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

---

## Production Features

### Host Optimization

```bash
sudo ./scripts/optimize-host.sh
```

Configures:
- Disables Transparent Huge Pages (reduces latency spikes)
- Sets `vm.overcommit_memory=1` (prevents background save failures)
- Increases TCP backlog and file descriptors
- Optimizes TCP keepalive settings

### Automated Backups

```bash
# Manual
VALKEY_PASSWORD=your-password ./scripts/backup.sh /backups

# Cron (every 6 hours)
0 */6 * * * VALKEY_PASSWORD=your-password /path/to/backup.sh /backups
```

### Monitoring

```bash
cd monitoring
VALKEY_PASSWORD=your-password docker compose up -d
```

Metrics at `http://localhost:9121/metrics`

### Let's Encrypt Auto-Renewal

```bash
sudo ln -sf $(pwd)/scripts/renew-certs.sh /etc/letsencrypt/renewal-hooks/deploy/valkey-ssl.sh
```

---

## Sentinel HA (Alternative to Cluster)

For automatic failover without data sharding. Use when:
- Data fits on one server
- Need HA with automatic failover
- Don't need horizontal scaling

**Architecture:** 1 Master + 2 Replicas + 3 Sentinels across 3 servers

### Setup (3 servers)

**Generate certs (once):**
```bash
cd sentinel
../scripts/generate-certs.sh ./certs sentinel.local 365
```

**Server 1 (Master):**
```bash
./generate-sentinel-config.sh master 10.0.0.1 10.0.0.1 mysecret
# Or with domain:
./generate-sentinel-config.sh master redis1.example.com redis1.example.com mysecret
sudo ufw allow 6379/tcp && sudo ufw allow 26379/tcp
docker compose up -d
```

**Server 2 (Replica):**
```bash
# Copy certs from server 1
scp -r user@server1:/path/to/sentinel/certs ./
./generate-sentinel-config.sh replica 10.0.0.2 10.0.0.1 mysecret
sudo ufw allow 6379/tcp && sudo ufw allow 26379/tcp
docker compose up -d
```

**Server 3 (Replica):**
```bash
# Copy certs from server 1
scp -r user@server1:/path/to/sentinel/certs ./
./generate-sentinel-config.sh replica 10.0.0.3 10.0.0.1 mysecret
sudo ufw allow 6379/tcp && sudo ufw allow 26379/tcp
docker compose up -d
```

### Verify

```bash
# Check sentinel status
docker exec valkey-sentinel valkey-cli --tls --insecure -p 26379 SENTINEL masters

# Check replication
docker exec valkey valkey-cli --tls --insecure -a mysecret INFO replication
```

### Client Connection

Clients should connect to Sentinel to discover the current master:

**Node.js:**
```javascript
const Redis = require('ioredis');
const redis = new Redis({
  sentinels: [
    { host: '10.0.0.1', port: 26379 },
    { host: '10.0.0.2', port: 26379 },
    { host: '10.0.0.3', port: 26379 }
  ],
  name: 'mymaster',
  password: 'mysecret',
  tls: {}
});
```

---

## File Structure

```
valkey-ssl/
├── setup.sh                        # One-command setup (interactive)
├── teardown.sh                     # Cleanup script
├── docker-compose.yml              # Standalone deployment
├── .env.example                    # Environment template
├── config/
│   └── valkey.conf.example         # Config template (optimized)
├── certs/                          # SSL certificates (generated)
├── data/                           # Persistent data
├── scripts/
│   ├── generate-certs.sh           # Self-signed cert generator
│   ├── renew-certs.sh              # Let's Encrypt renewal
│   ├── backup.sh                   # Automated backups
│   ├── optimize-host.sh            # OS/kernel tuning
│   └── test-connection.sh          # Connection tester
├── cluster/
│   ├── docker-compose.yml              # Single-server cluster
│   ├── docker-compose.multi-server.yml # Multi-server cluster
│   ├── generate-cluster-config.sh      # Single-server config
│   ├── generate-multiserver-config.sh  # Multi-server config
│   ├── init-cluster.sh                 # Single-server init
│   └── init-multiserver-cluster.sh     # Multi-server init
├── sentinel/
│   ├── docker-compose.yml              # Sentinel deployment
│   └── generate-sentinel-config.sh     # Config generator
└── monitoring/
    ├── docker-compose.yml          # Prometheus exporter
    └── prometheus.yml              # Prometheus config
```

## License

BSD-3-Clause (same as Valkey)
