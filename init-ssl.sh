#!/bin/bash
# =============================================================================
# Let's Encrypt SSL Certificate Initialization Script
# =============================================================================
# Run this script ONCE to obtain initial SSL certificates
# After initial setup, certbot container handles automatic renewal
# =============================================================================

set -e

# Load environment variables
if [ -f .env ]; then
    export $(cat .env | grep -v '^#' | xargs)
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

# Check if certificates already exist
if [ -d "./certbot/conf/live/$DOMAIN" ]; then
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
if [ -f "nginx/conf.d/cdsconnect.conf" ]; then
    mv nginx/conf.d/cdsconnect.conf nginx/conf.d/cdsconnect.conf.ssl
fi

if [ -f "nginx/conf.d/cdsconnect-init.conf" ]; then
    cp nginx/conf.d/cdsconnect-init.conf nginx/conf.d/cdsconnect.conf
fi

# Start nginx
docker-compose up -d nginx
sleep 5

# Request certificate
echo "Step 2: Requesting SSL certificate from Let's Encrypt..."

STAGING_ARG=""
if [ "$STAGING" = "1" ]; then
    STAGING_ARG="--staging"
    echo "Using Let's Encrypt STAGING environment (certificates will NOT be valid)"
fi

docker-compose run --rm certbot certonly \
    --webroot \
    --webroot-path=/var/www/certbot \
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

# Restart nginx with SSL config
echo "Step 4: Restarting nginx with SSL..."
docker-compose restart nginx

echo "============================================="
echo "SSL Setup Complete!"
echo "============================================="
echo "Your site should now be accessible at:"
echo "  https://$DOMAIN"
echo "  https://www.$DOMAIN"
echo ""
echo "Certificates will auto-renew via certbot container"
echo "============================================="