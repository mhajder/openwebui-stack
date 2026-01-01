#!/bin/bash
# =============================================================================
# Generate Self-Signed Certificates for Traefik
# =============================================================================
# This script generates self-signed SSL certificates for local development
# For production, use Let's Encrypt or proper CA-signed certificates

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CERTS_DIR="$PROJECT_ROOT/certs"

# Certificate configuration
DOMAIN="${DOMAIN:-localhost}"
DAYS_VALID=365
KEY_SIZE=4096

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Generating Self-Signed Certificates ===${NC}"
echo "Domain: $DOMAIN"
echo "Validity: $DAYS_VALID days"
echo "Key Size: $KEY_SIZE bits"
echo ""

# Create certs directory if it doesn't exist
mkdir -p "$CERTS_DIR"

# Generate private key
echo -e "${YELLOW}Generating private key...${NC}"
openssl genrsa -out "$CERTS_DIR/server.key" $KEY_SIZE

# Create OpenSSL config for SAN (Subject Alternative Names)
cat >"$CERTS_DIR/openssl.cnf" <<EOF
[req]
default_bits = $KEY_SIZE
prompt = no
default_md = sha256
x509_extensions = v3_req
distinguished_name = dn

[dn]
C = US
ST = State
L = City
O = Open WebUI Stack
OU = Development
CN = $DOMAIN

[v3_req]
subjectAltName = @alt_names
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth

[alt_names]
DNS.1 = $DOMAIN
DNS.2 = *.$DOMAIN
DNS.3 = localhost
DNS.4 = *.localhost
IP.1 = 127.0.0.1
IP.2 = ::1
EOF

# Generate self-signed certificate
echo -e "${YELLOW}Generating self-signed certificate...${NC}"
openssl req -new -x509 \
    -key "$CERTS_DIR/server.key" \
    -out "$CERTS_DIR/server.crt" \
    -days $DAYS_VALID \
    -config "$CERTS_DIR/openssl.cnf"

# Set appropriate permissions
chmod 600 "$CERTS_DIR/server.key"
chmod 644 "$CERTS_DIR/server.crt"

# Verify certificate
echo -e "${YELLOW}Verifying certificate...${NC}"
openssl x509 -in "$CERTS_DIR/server.crt" -text -noout | head -20

echo ""
echo -e "${GREEN}=== Certificates Generated Successfully ===${NC}"
echo "Certificate: $CERTS_DIR/server.crt"
echo "Private Key: $CERTS_DIR/server.key"
echo ""
echo -e "${YELLOW}Note: These are self-signed certificates for development.${NC}"
echo -e "${YELLOW}For production, use Let's Encrypt or CA-signed certificates.${NC}"
