#!/bin/bash
# =============================================================================
# CDS Connect Deployment Script
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check for .env file
if [ ! -f .env ]; then
    log_error ".env file not found!"
    log_info "Copy .env.example to .env and configure it:"
    log_info "  cp .env.example .env"
    exit 1
fi

# Load environment
export $(cat .env | grep -v '^#' | xargs)

case "$1" in
    start)
        log_info "Starting CDS Connect services..."
        docker-compose up -d
        docker-compose ps
        ;;

    stop)
        log_info "Stopping CDS Connect services..."
        docker-compose down
        ;;

    restart)
        log_info "Restarting CDS Connect services..."
        docker-compose restart
        ;;

    update)
        log_info "Updating CDS Connect services..."
        docker-compose pull
        docker-compose up -d
        docker-compose ps
        log_info "Update complete!"
        ;;

    logs)
        SERVICE=${2:-}
        if [ -n "$SERVICE" ]; then
            docker-compose logs -f "$SERVICE"
        else
            docker-compose logs -f
        fi
        ;;

    status)
        docker-compose ps
        echo ""
        log_info "Health checks:"
        echo -n "  CQL Services: "
        curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/ || echo "unreachable"
        echo ""
        echo -n "  Authoring API: "
        curl -s -o /dev/null -w "%{http_code}" http://localhost:3001/authoring/api/config || echo "unreachable"
        echo ""
        ;;

    backup)
        BACKUP_DIR="./backups/$(date +%Y%m%d-%H%M%S)"
        mkdir -p "$BACKUP_DIR"
        log_info "Backing up MongoDB to $BACKUP_DIR..."
        docker-compose exec -T mongodb mongodump --archive > "$BACKUP_DIR/mongodb.archive"
        log_info "Backup complete: $BACKUP_DIR/mongodb.archive"
        ;;

    restore)
        if [ -z "$2" ]; then
            log_error "Please specify backup file: ./deploy.sh restore <backup-file>"
            exit 1
        fi
        log_warn "This will OVERWRITE the current database!"
        read -p "Are you sure? (y/N) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log_info "Restoring from $2..."
            cat "$2" | docker-compose exec -T mongodb mongorestore --archive --drop
            log_info "Restore complete!"
        fi
        ;;

    ssl-init)
        log_info "Initializing SSL certificates..."
        chmod +x init-ssl.sh
        ./init-ssl.sh
        ;;

    ssl-renew)
        log_info "Renewing SSL certificates..."
        docker-compose run --rm certbot renew
        docker-compose restart nginx
        ;;

    shell)
        SERVICE=${2:-cql-services}
        log_info "Opening shell in $SERVICE..."
        docker-compose exec "$SERVICE" /bin/sh
        ;;

    *)
        echo "CDS Connect Deployment Script"
        echo ""
        echo "Usage: $0 <command> [options]"
        echo ""
        echo "Commands:"
        echo "  start       Start all services"
        echo "  stop        Stop all services"
        echo "  restart     Restart all services"
        echo "  update      Pull latest images and restart"
        echo "  logs [svc]  View logs (optionally for specific service)"
        echo "  status      Show service status and health"
        echo "  backup      Backup MongoDB database"
        echo "  restore <f> Restore MongoDB from backup file"
        echo "  ssl-init    Initialize Let's Encrypt certificates"
        echo "  ssl-renew   Force SSL certificate renewal"
        echo "  shell [svc] Open shell in service (default: cql-services)"
        echo ""
        echo "Services: nginx, cql-services, authoring-api, authoring-frontend,"
        echo "          mongodb, cql-to-elm, certbot"
        ;;
esac