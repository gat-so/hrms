#!/bin/bash
# Initial VPS setup script for HRMS deployment
# Run this once on a fresh Ubuntu 24.04 VPS
set -e

echo "=== HRMS VPS Setup ==="

# Update system
sudo apt update && sudo apt upgrade -y

# Install Docker if not already installed
if ! command -v docker &> /dev/null; then
    echo "Installing Docker..."
    curl -fsSL https://get.docker.com | bash
    sudo usermod -aG docker $USER
    echo "Docker installed."
fi

# Ensure docker commands work in this session
if ! docker info &> /dev/null; then
    echo "Applying docker group for current session..."
    exec sg docker "$0 $*"
fi

# Install Docker Compose plugin if not present
if ! docker compose version &> /dev/null; then
    echo "Installing Docker Compose plugin..."
    sudo apt install -y docker-compose-plugin
fi

# Create directory structure
echo "Creating directory structure..."
sudo mkdir -p /opt/hrms/{prod,dev,preview}
sudo mkdir -p /opt/hrms/traefik
sudo chown -R $USER:$USER /opt/hrms

# Set up Traefik (shared reverse proxy)
echo "Setting up Traefik..."
read -p "Enter your email for Let's Encrypt certificates: " ACME_EMAIL
read -p "Enter the domain for Traefik dashboard (e.g., traefik.yourdomain.com): " DASHBOARD_DOMAIN
read -p "Enter Traefik dashboard username: " DASHBOARD_USER
read -sp "Enter Traefik dashboard password: " DASHBOARD_PASS
echo

# Generate htpasswd for Traefik dashboard
DASHBOARD_AUTH=$(docker run --rm httpd:2.4-alpine htpasswd -nbB "$DASHBOARD_USER" "$DASHBOARD_PASS" | sed -e 's/\$/\$\$/g')

cat > /opt/hrms/traefik/.env << EOF
ACME_EMAIL=${ACME_EMAIL}
TRAEFIK_DASHBOARD_DOMAIN=${DASHBOARD_DOMAIN}
TRAEFIK_DASHBOARD_AUTH=${DASHBOARD_AUTH}
EOF

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Next steps:"
echo "  1. Copy deploy/traefik/docker-compose.yml to /opt/hrms/traefik/"
echo "  2. Start Traefik:  cd /opt/hrms/traefik && docker compose up -d"
echo "  3. Configure DNS A records pointing to this VPS IP:"
echo "     - hrms.yourdomain.com       → VPS IP (production)"
echo "     - dev.hrms.yourdomain.com   → VPS IP (development)"
echo "     - *.preview.yourdomain.com  → VPS IP (PR previews)"
echo "     - traefik.yourdomain.com    → VPS IP (Traefik dashboard)"
echo "  4. Set up environment files in /opt/hrms/prod/.env and /opt/hrms/dev/.env"
echo "  5. Add SSH keys and environment variables to CircleCI"
echo ""
