#!/bin/bash
# SPDX-FileCopyrightText: (C) 2026 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

set -euo pipefailgt

# Set working directory for SSL certificates
SSL_DIR="/opt/nginx/certs"
mkdir -p "$SSL_DIR"

# Set default values for SSL parameters if not provided
KEY_LENGTH=3072
DAYS=365
SHA_ALGO="sha384"

echo "Generating SSL certificates for Nginx..."
rm -f "$SSL_DIR/key.pem" "$SSL_DIR/cert.pem"

openssl req -x509 -nodes -days "${DAYS}" -"${SHA_ALGO}" -newkey "rsa:${KEY_LENGTH}" \
    -keyout "$SSL_DIR/key.pem" -out "$SSL_DIR/cert.pem" -subj "/CN=localhost" \
    -addext "basicConstraints=critical,CA:TRUE" \
    -addext "keyUsage=critical,digitalSignature,keyEncipherment,keyCertSign,cRLSign" \
    -addext "extendedKeyUsage=serverAuth" \
    -addext "subjectAltName=DNS:localhost,IP:127.0.0.1"
chmod 640 "$SSL_DIR/key.pem" "$SSL_DIR/cert.pem"
