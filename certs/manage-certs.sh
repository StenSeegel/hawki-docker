#!/bin/bash
set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Function to display help
show_help() {
    echo ""
    echo "═══════════════════════════════════════════════════════"
    echo "🔐 HAWKI Certificate Management"
    echo "═══════════════════════════════════════════════════════"
    echo ""
    echo "Usage: ./manage-certs.sh [COMMAND]"
    echo ""
    echo "Commands:"
    echo "  find        Find existing server certificates"
    echo "  copy        Copy certificates from another location"
    echo "  generate    Generate self-signed development certificates"
    echo "  help        Show this help message"
    echo ""
    echo "Examples:"
    echo "  ./manage-certs.sh find"
    echo "  ./manage-certs.sh copy /path/to/source/certs"
    echo "  ./manage-certs.sh generate app.hawki.dev"
    echo ""
    echo "═══════════════════════════════════════════════════════"
    echo ""
}

# Function to find server certificates
find_certs() {
    echo ""
    echo -e "${BLUE}🔍 Searching for server certificates...${NC}"
    echo ""
    
    # Common certificate locations
    CERT_LOCATIONS=(
        "/etc/ssl/certs"
        "/etc/pki/tls/certs"
        "/etc/nginx/ssl"
        "/etc/apache2/ssl"
        "/usr/local/etc/nginx/ssl"
        "$HOME/.ssh"
        "$HOME/ssl"
        "$HOME/certs"
    )
    
    echo "Checking common locations:"
    for location in "${CERT_LOCATIONS[@]}"; do
        if [ -d "$location" ]; then
            echo -e "${GREEN}✓${NC} $location"
            cert_files=$(find "$location" -maxdepth 2 -type f \( -name "*.crt" -o -name "*.pem" -o -name "*.key" \) 2>/dev/null || true)
            if [ -n "$cert_files" ]; then
                echo "$cert_files" | while read -r file; do
                    echo "  - $file"
                done
            fi
        else
            echo -e "${YELLOW}○${NC} $location (not found)"
        fi
    done
    
    echo ""
    echo "Certificates in current directory ($SCRIPT_DIR):"
    if ls "$SCRIPT_DIR"/*.{crt,pem,key} 2>/dev/null; then
        echo ""
    else
        echo -e "${YELLOW}  No certificates found${NC}"
    fi
    
    echo ""
}

# Function to copy certificates
copy_certs() {
    local source_dir="$1"
    
    if [ -z "$source_dir" ]; then
        echo -e "${RED}❌ Error: Please specify source directory${NC}"
        echo "Usage: ./manage-certs.sh copy /path/to/source/certs"
        exit 1
    fi
    
    if [ ! -d "$source_dir" ]; then
        echo -e "${RED}❌ Error: Source directory does not exist: $source_dir${NC}"
        exit 1
    fi
    
    echo ""
    echo -e "${BLUE}📋 Copying certificates from: $source_dir${NC}"
    echo ""
    
    # Count certificate files
    cert_count=$(find "$source_dir" -maxdepth 1 -type f \( -name "*.crt" -o -name "*.pem" -o -name "*.key" \) | wc -l)
    
    if [ "$cert_count" -eq 0 ]; then
        echo -e "${YELLOW}⚠️  No certificate files found in source directory${NC}"
        exit 1
    fi
    
    echo "Found $cert_count certificate file(s)"
    echo ""
    
    # Copy files
    find "$source_dir" -maxdepth 1 -type f \( -name "*.crt" -o -name "*.pem" -o -name "*.key" \) -exec cp -v {} "$SCRIPT_DIR/" \;
    
    echo ""
    echo -e "${GREEN}✅ Certificates copied successfully!${NC}"
    echo ""
    
    # Set appropriate permissions
    echo "Setting file permissions..."
    chmod 644 "$SCRIPT_DIR"/*.crt 2>/dev/null || true
    chmod 644 "$SCRIPT_DIR"/*.pem 2>/dev/null || true
    chmod 600 "$SCRIPT_DIR"/*.key 2>/dev/null || true
    
    echo -e "${GREEN}✅ Permissions set${NC}"
    echo ""
}

# Function to generate development certificates
generate_dev_certs() {
    local domain="$1"
    
    if [ -z "$domain" ]; then
        echo -e "${YELLOW}⚠️  No domain specified, using default: app.hawki.dev${NC}"
        domain="app.hawki.dev"
    fi
    
    echo ""
    echo -e "${BLUE}🔐 Generating self-signed certificate for: $domain${NC}"
    echo ""
    
    # Check if openssl is available
    if ! command -v openssl &> /dev/null; then
        echo -e "${RED}❌ Error: openssl is not installed${NC}"
        echo "Please install openssl first"
        exit 1
    fi
    
    # Create temporary OpenSSL config for SAN (Subject Alternative Name)
    # Modern browsers (Chrome 58+) require SAN extension
    local config_file="$SCRIPT_DIR/openssl-san-${domain}.cnf"
    
    echo "Creating OpenSSL configuration..."
    cat > "$config_file" << EOF
[req]
default_bits = 2048
prompt = no
default_md = sha256
x509_extensions = v3_req
distinguished_name = dn

[dn]
C = DE
ST = Lower Saxony
L = Hildesheim
O = HAWKI Dev
CN = $domain

[v3_req]
subjectAltName = @alt_names

[alt_names]
DNS.1 = $domain
DNS.2 = localhost
IP.1 = 127.0.0.1
EOF
    
    # Generate certificate with proper SAN extension
    echo "Generating certificate with SAN extension..."
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "$SCRIPT_DIR/${domain}.key" \
        -out "$SCRIPT_DIR/${domain}.crt" \
        -config "$config_file" \
        > /dev/null 2>&1
    
    # Clean up temporary config file
    rm -f "$config_file"
    
    # Set permissions
    chmod 600 "$SCRIPT_DIR/${domain}.key"
    chmod 644 "$SCRIPT_DIR/${domain}.crt"
    
    echo ""
    echo -e "${GREEN}✅ Certificate generated successfully!${NC}"
    echo ""
    echo "Generated files:"
    echo "  - $SCRIPT_DIR/${domain}.key (private key)"
    echo "  - $SCRIPT_DIR/${domain}.crt (certificate)"
    echo ""
    
    # Also generate generic cert.pem and key.pem if they don't exist
    if [ ! -f "$SCRIPT_DIR/cert.pem" ]; then
        cp "$SCRIPT_DIR/${domain}.crt" "$SCRIPT_DIR/cert.pem"
        echo "Created generic cert.pem"
    fi
    
    if [ ! -f "$SCRIPT_DIR/key.pem" ]; then
        cp "$SCRIPT_DIR/${domain}.key" "$SCRIPT_DIR/key.pem"
        echo "Created generic key.pem"
    fi
    
    echo ""
    
    # Add to macOS keychain if possible
    if command -v security &> /dev/null; then
        echo -e "${YELLOW}🔐 Adding certificate to macOS keychain...${NC}"
        if sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain "$SCRIPT_DIR/${domain}.crt" 2>/dev/null; then
            echo -e "${GREEN}✅ Certificate added to keychain${NC}"
        else
            echo -e "${YELLOW}⚠️  Could not add to keychain (requires sudo)${NC}"
        fi
        echo ""
    fi
    
    echo -e "${YELLOW}⚠️  Note: These are self-signed certificates for development only!${NC}"
    echo "For production, use certificates from a trusted CA."
    echo ""
    
    # Check if domain is in /etc/hosts
    if [ "$domain" != "localhost" ] && [ "$domain" != "127.0.0.1" ]; then
        if ! grep -q "$domain" /etc/hosts 2>/dev/null; then
            echo -e "${YELLOW}💡 Tip: Add this domain to /etc/hosts:${NC}"
            echo "   sudo sh -c 'echo \"127.0.0.1 $domain\" >> /etc/hosts'"
            echo ""
        fi
    fi
}

# Main script logic
case "${1:-help}" in
    find)
        find_certs
        ;;
    copy)
        copy_certs "$2"
        ;;
    generate)
        generate_dev_certs "$2"
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        echo -e "${RED}❌ Unknown command: $1${NC}"
        show_help
        exit 1
        ;;
esac
