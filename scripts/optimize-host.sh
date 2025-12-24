#!/bin/bash
# Host OS optimization for Valkey
# Run as root: sudo ./optimize-host.sh

set -e

echo "=== Optimizing Host for Valkey ==="

# 1. Disable Transparent Huge Pages (causes latency spikes)
echo "Disabling Transparent Huge Pages..."
echo never > /sys/kernel/mm/transparent_hugepage/enabled
echo never > /sys/kernel/mm/transparent_hugepage/defrag

# Make persistent across reboots
cat >> /etc/rc.local << 'EOF'
echo never > /sys/kernel/mm/transparent_hugepage/enabled
echo never > /sys/kernel/mm/transparent_hugepage/defrag
EOF

# 2. Kernel tuning
echo "Applying kernel optimizations..."
cat >> /etc/sysctl.conf << 'EOF'

# Valkey Optimizations
vm.overcommit_memory = 1
vm.swappiness = 1
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_keepalive_intvl = 15
net.ipv4.tcp_tw_reuse = 1
fs.file-max = 2097152
EOF

sysctl -p

# 3. Increase file descriptor limits
echo "Increasing file descriptor limits..."
cat >> /etc/security/limits.conf << 'EOF'
* soft nofile 65536
* hard nofile 65536
* soft nproc 65536
* hard nproc 65536
EOF

# 4. Disable swap (optional - for dedicated Valkey servers)
# swapoff -a

echo ""
echo "=== Optimization Complete ==="
echo "Please REBOOT for all changes to take effect"
