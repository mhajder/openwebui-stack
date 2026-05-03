#!/bin/bash
# =============================================================================
# Open WebUI Stack - Setup Script
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Cross-platform sed in-place editing (macOS BSD sed vs GNU sed)
sed_inplace() {
    if [[ $OSTYPE == "darwin"* ]]; then
        sed -i '' "$@"
    else
        sed -i "$@"
    fi
}

# Helper function to generate htpasswd hash (apr1 format)
generate_htpasswd() {
    local password="$1"
    openssl passwd -apr1 "$password"
}

# Helper function to generate password
generate_password() {
    openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 32
}

# Helper function for yes/no prompt (defaults to yes)
prompt_yes_no() {
    local prompt="$1"
    local response
    read -rp "$prompt (Y/n): " response
    response=${response:-y}
    case "$response" in
    [yY][eE][sS] | [yY]) return 0 ;;
    [nN][oO] | [nN]) return 1 ;;
    *) return 0 ;; # Default to yes on invalid input
    esac
}

# Helper function for yes/no prompt (defaults to no)
prompt_yes_no_default_no() {
    local prompt="$1"
    local response
    read -rp "$prompt (y/N): " response
    response=${response:-n}
    case "$response" in
    [yY][eE][sS] | [yY]) return 0 ;;
    [nN][oO] | [nN]) return 1 ;;
    *) return 1 ;; # Default to no on invalid input
    esac
}

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Open WebUI Stack - Setup${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# 1. Initialize .env file
echo -e "${YELLOW}Step 1: Environment File${NC}"
if [ -f "$PROJECT_ROOT/.env" ]; then
    echo -e "${GREEN}✓ .env file already exists${NC}"
    if prompt_yes_no_default_no "Override existing .env file?"; then
        INIT_ENV=true
    else
        INIT_ENV=false
    fi
else
    if prompt_yes_no "Initialize .env file?"; then
        INIT_ENV=true
    else
        INIT_ENV=false
    fi
fi
echo ""

# 2. Domain
echo -e "${YELLOW}Step 2: Domain Configuration${NC}"
read -rp "Enter your domain (default: localhost): " DOMAIN
DOMAIN=${DOMAIN:-localhost}
echo -e "${GREEN}✓ Domain: $DOMAIN${NC}"
echo ""

# 3. Generate passwords
GENERATE_PASSWORDS=false
if [ "$INIT_ENV" = true ]; then
    echo -e "${YELLOW}Step 3: Generate Passwords${NC}"
    if prompt_yes_no "Generate secure passwords for .env?"; then
        GENERATE_PASSWORDS=true
    fi
    echo ""
fi

# 4. SSL Certificates (optional)
echo -e "${YELLOW}Step 4: SSL Certificates${NC}"
echo -e "  Traefik generates a self-signed certificate by default."
echo -e "  It changes on every restart, requiring you to re-accept it in the browser."
echo -e "  Generating persistent certificates avoids this."
GENERATE_CERTS=false
if [ -f "$PROJECT_ROOT/certs/server.crt" ] && [ -f "$PROJECT_ROOT/certs/server.key" ]; then
    echo -e "${GREEN}✓ Custom certificates already exist${NC}"
    if prompt_yes_no_default_no "Regenerate certificates?"; then
        GENERATE_CERTS=true
    fi
else
    if prompt_yes_no_default_no "Generate persistent self-signed certificates?"; then
        GENERATE_CERTS=true
    fi
fi
echo ""

# Execute steps
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "Executing setup..."
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Initialize .env
if [ "$INIT_ENV" = true ]; then
    if [ -f "$PROJECT_ROOT/.env.example" ]; then
        cp "$PROJECT_ROOT/.env.example" "$PROJECT_ROOT/.env"
        echo -e "${GREEN}✓ Created .env file${NC}"
    else
        echo -e "${RED}✗ .env.example not found${NC}"
        exit 1
    fi
fi

# Set domain in .env
if [ -f "$PROJECT_ROOT/.env" ]; then
    sed_inplace "s/DOMAIN=.*/DOMAIN=$DOMAIN/g" "$PROJECT_ROOT/.env"
    echo -e "${GREEN}✓ Set domain to: $DOMAIN${NC}"
fi

# Generate passwords
if [ "$GENERATE_PASSWORDS" = true ]; then
    # Generate all plain text passwords first
    POSTGRES_PASS=$(generate_password)
    OPENWEBUI_DB_PASS=$(generate_password)
    LITELLM_DB_PASS=$(generate_password)
    OPENWEBUI_SECRET=$(generate_password)
    LITELLM_MASTER=sk-$(generate_password)
    LITELLM_SALT=$(generate_password)
    GRAFANA_PASS=$(generate_password)
    QDRANT_KEY=$(generate_password)
    VALKEY_PASS=$(generate_password)
    TRAEFIK_PASS=$(generate_password)

    # Replace all passwords with specific line patterns to avoid substring matches
    sed_inplace "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=$POSTGRES_PASS|" "$PROJECT_ROOT/.env"
    sed_inplace "s|^OPENWEBUI_DB_PASSWORD=.*|OPENWEBUI_DB_PASSWORD=$OPENWEBUI_DB_PASS|" "$PROJECT_ROOT/.env"
    sed_inplace "s|^LITELLM_DB_PASSWORD=.*|LITELLM_DB_PASSWORD=$LITELLM_DB_PASS|" "$PROJECT_ROOT/.env"
    sed_inplace "s|^OPENWEBUI_SECRET_KEY=.*|OPENWEBUI_SECRET_KEY=$OPENWEBUI_SECRET|" "$PROJECT_ROOT/.env"
    sed_inplace "s|^LITELLM_MASTER_KEY=.*|LITELLM_MASTER_KEY=$LITELLM_MASTER|" "$PROJECT_ROOT/.env"
    sed_inplace "s|^LITELLM_SALT_KEY=.*|LITELLM_SALT_KEY=$LITELLM_SALT|" "$PROJECT_ROOT/.env"
    sed_inplace "s|^GF_SECURITY_ADMIN_PASSWORD=.*|GF_SECURITY_ADMIN_PASSWORD=$GRAFANA_PASS|" "$PROJECT_ROOT/.env"
    sed_inplace "s|^QDRANT_API_KEY=.*|QDRANT_API_KEY=$QDRANT_KEY|" "$PROJECT_ROOT/.env"
    sed_inplace "s|^VALKEY_PASSWORD=.*|VALKEY_PASSWORD=$VALKEY_PASS|" "$PROJECT_ROOT/.env"
    sed_inplace "s|^TRAEFIK_DASHBOARD_PASSWORD=.*|TRAEFIK_DASHBOARD_PASSWORD=$TRAEFIK_PASS|" "$PROJECT_ROOT/.env"

    # Generate Traefik dashboard password hash from the plain password we just set
    TRAEFIK_HASH=$(generate_htpasswd "$TRAEFIK_PASS")
    # Escape $ signs for Docker Compose variable interpolation (apr1 hashes use $ in format)
    # Also escape special characters for sed
    ESCAPED_HASH=$(echo "$TRAEFIK_HASH" | sed 's/\$/$$/g' | sed 's/[\/&]/\\&/g')
    sed_inplace "s|^TRAEFIK_DASHBOARD_PASSWORD_HASH=.*|TRAEFIK_DASHBOARD_PASSWORD_HASH=$ESCAPED_HASH|" "$PROJECT_ROOT/.env"

    echo -e "${GREEN}✓ Generated secure passwords${NC}"
fi

# Generate SSL certificates
if [ "$GENERATE_CERTS" = true ]; then
    export DOMAIN
    "$SCRIPT_DIR/generate-certs.sh"
fi

# Make scripts executable
chmod +x "$SCRIPT_DIR"/*.sh

echo ""
echo -e "${GREEN}✓ Setup complete!${NC}"
echo ""
