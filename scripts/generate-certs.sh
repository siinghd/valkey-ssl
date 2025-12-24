#!/bin/bash
# Valkey SSL Certificate Generator
# Generates CA, server, and client certificates for Valkey TLS

set -e

CERTS_DIR="${1:-../certs}"
DOMAIN="${2:-localhost}"
DAYS="${3:-365}"

mkdir -p "$CERTS_DIR"
cd "$CERTS_DIR"

echo "=== Generating Valkey SSL Certificates ==="
echo "Domain: $DOMAIN"
echo "Validity: $DAYS days"
echo ""

# Generate CA private key
echo "1. Generating CA private key..."
openssl genrsa -out ca.key 4096

# Generate CA certificate
echo "2. Generating CA certificate..."
openssl req -new -x509 -days $DAYS -key ca.key -out ca.crt \
    -subj "/C=US/ST=State/L=City/O=Valkey-SSL/OU=CA/CN=Valkey-CA"

# Generate server private key
echo "3. Generating server private key..."
openssl genrsa -out valkey.key 4096

# Generate server certificate signing request
echo "4. Generating server CSR..."
openssl req -new -key valkey.key -out valkey.csr \
    -subj "/C=US/ST=State/L=City/O=Valkey-SSL/OU=Server/CN=$DOMAIN"

# Create extension file for SAN (Subject Alternative Names)
cat > valkey.ext << EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = $DOMAIN
DNS.2 = localhost
DNS.3 = valkey
IP.1 = 127.0.0.1
EOF

# Sign server certificate with CA
echo "5. Signing server certificate..."
openssl x509 -req -in valkey.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
    -out valkey.crt -days $DAYS -extfile valkey.ext

# Generate client private key (for mTLS)
echo "6. Generating client private key..."
openssl genrsa -out client.key 4096

# Generate client certificate signing request
echo "7. Generating client CSR..."
openssl req -new -key client.key -out client.csr \
    -subj "/C=US/ST=State/L=City/O=Valkey-SSL/OU=Client/CN=valkey-client"

# Create client extension file
cat > client.ext << EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = clientAuth
EOF

# Sign client certificate with CA
echo "8. Signing client certificate..."
openssl x509 -req -in client.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
    -out client.crt -days $DAYS -extfile client.ext

# Set permissions (readable for Docker containers)
chmod 644 *.key *.crt

# Clean up temporary files
rm -f *.csr *.ext *.srl

echo ""
echo "=== Certificates Generated Successfully ==="
echo ""
echo "Files created in $CERTS_DIR:"
ls -la

echo ""
echo "CA Certificate:     ca.crt"
echo "Server Certificate: valkey.crt"
echo "Server Key:         valkey.key"
echo "Client Certificate: client.crt (for mTLS)"
echo "Client Key:         client.key (for mTLS)"
