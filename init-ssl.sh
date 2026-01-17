#!/bin/bash
# =============================================================================
# Let's Encrypt SSL Certificate Initialization Script
# =============================================================================
# Run this script ONCE to obtain initial SSL certificates
# After initial setup, certbot container handles automatic renewal
# =============================================================================

set -e

# Load environment variables (handle values with special characters)
if [ -f .env ]; then
    set -a
    source .env
    set +a
fi

# Configuration
DOMAIN=${DOMAIN:-cdsconnect.org}
EMAIL=${LETSENCRYPT_EMAIL:-admin@$DOMAIN}
STAGING=${STAGING:-0}  # Set to 1 for testing (avoids rate limits)

echo "============================================="
echo "CDS Connect SSL Certificate Setup"
echo "============================================="
echo "Domain: $DOMAIN"
echo "Email: $EMAIL"
echo "Staging: $STAGING"
echo "============================================="

# Check if certificates already exist in the volume
CERT_EXISTS=$(docker run --rm -v cds-certbot-etc:/etc/letsencrypt alpine ls /etc/letsencrypt/live/$DOMAIN 2>/dev/null || echo "no")
if [ "$CERT_EXISTS" != "no" ]; then
    echo "Certificates already exist for $DOMAIN"
    read -p "Do you want to renew/replace them? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 0
    fi
fi

# Ensure nginx is running with init config
echo "Step 1: Preparing nginx for certificate challenge..."

# Backup SSL config and use init config
if [ -f "nginx/conf.d/cdsconnect.conf" ] && [ ! -f "nginx/conf.d/cdsconnect.conf.ssl" ]; then
    mv nginx/conf.d/cdsconnect.conf nginx/conf.d/cdsconnect.conf.ssl
fi

if [ -f "nginx/conf.d/cdsconnect-init.conf.example" ]; then
    cp nginx/conf.d/cdsconnect-init.conf.example nginx/conf.d/cdsconnect.conf
fi

# Stop all services first
docker compose down 2>/dev/null || true

# Start only nginx
docker compose up -d nginx
sleep 5

# Verify nginx is running
if ! docker compose ps nginx | grep -q "Up"; then
    echo "ERROR: nginx failed to start. Check logs with: docker compose logs nginx"
    exit 1
fi

# Request certificate
echo "Step 2: Requesting SSL certificate from Let's Encrypt..."

STAGING_ARG=""
if [ "$STAGING" = "1" ]; then
    STAGING_ARG="--staging"
    echo "Using Let's Encrypt STAGING environment (certificates will NOT be valid)"
fi

# Stop nginx to free port 80 for standalone mode
docker compose stop nginx

# Use standalone mode (more reliable)
docker run -it --rm \
    -p 80:80 \
    -v cds-certbot-etc:/etc/letsencrypt \
    -v cds-certbot-var:/var/lib/letsencrypt \
    certbot/certbot certonly \
    --standalone \
    $STAGING_ARG \
    --email $EMAIL \
    --agree-tos \
    --no-eff-email \
    -d $DOMAIN \
    -d www.$DOMAIN

# Restore SSL config
echo "Step 3: Restoring SSL configuration..."

rm -f nginx/conf.d/cdsconnect.conf

if [ -f "nginx/conf.d/cdsconnect.conf.ssl" ]; then
    mv nginx/conf.d/cdsconnect.conf.ssl nginx/conf.d/cdsconnect.conf
fi

# Remove init config to avoid conflicts
rm -f nginx/conf.d/cdsconnect-init.conf

# Start all services
echo "Step 4: Starting all services..."
docker compose up -d

echo "============================================="
echo "SSL Setup Complete!"
echo "============================================="
echo "Your site should now be accessible at:"
echo "  https://$DOMAIN"
echo "  https://www.$DOMAIN"
echo ""
echo "Certificates will auto-renew via certbot container"
echo "============================================="