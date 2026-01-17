# CDS Connect Deployment

Infrastructure and deployment configuration for CDS Connect services.

## Related Repositories

| Repository | Description |
|------------|-------------|
| [iupui-soic/AHRQ-CDS-Connect-CQL-SERVICES](https://github.com/iupui-soic/AHRQ-CDS-Connect-CQL-SERVICES) | CQL Services (fork) |
| [iupui-soic/AHRQ-CDS-Connect-Authoring-Tool](https://github.com/iupui-soic/AHRQ-CDS-Connect-Authoring-Tool) | Authoring Tool (fork) |

## Architecture

```
┌───────────────────────────────────────────────────────────┐
│                    cdsconnect.org (nginx)                 │
│                   Let's Encrypt SSL/TLS                   │
└──────────────┬────────────────┬────────────────┬──────────┘
               │                │                │
   ┌───────────▼───────┐ ┌──────▼──────┐ ┌───────▼──────────┐
   │   /api/library    │ │/cds-services│ │   /authoring     │
   │   /               │ │             │ │   /authoring/api │
   └─────────┬─────────┘ └──────┬──────┘ └───────┬──────────┘
             │                  │                │
   ┌─────────▼──────────────────▼─────┐  ┌───────▼─────────┐
   │        CQL Services              │  │ Authoring Tool  │
   │     (ghcr.io/iupui-soic/...)     │  │  API + Frontend │
   └──────────────────────────────────┘  └──────┬──────────┘
                                                │
                              ┌─────────────────┼─────────────┐
                              │                 │             │
                        ┌─────▼─────┐    ┌──────▼─────┐ ┌─────▼──────┐
                        │  MongoDB  │    │ CQL-to-ELM │ │ VSAC Cache │
                        └───────────┘    └────────────┘ └────────────┘
```

## Quick Start

### 1. Clone and Configure

```bash
# On your production server
git clone https://github.com/iupui-soic/cds-connect-deployment.git
cd cds-connect-deployment

# Copy and edit environment variables
cp .env.example .env
nano .env  # Fill in required values
```

### 2. Add CQL Libraries and Hooks

```bash
# Create config directories
mkdir -p config/libraries config/hooks

# Copy your CQL libraries (ELM JSON files)
cp -r /path/to/your/libraries/* config/libraries/

# Copy your hook configurations
cp -r /path/to/your/hooks/* config/hooks/
```

### 3. Initialize SSL Certificates

```bash
# Make script executable
chmod +x init-ssl.sh

# Run SSL initialization (first time only)
./init-ssl.sh
```

### 4. Deploy

```bash
# Pull images and start all services
docker-compose pull
docker-compose up -d

# Check status
docker-compose ps

# View logs
docker-compose logs -f
```

## File Structure

```
cds-connect-deployment/
├── docker-compose.yml           # Service orchestration
├── .env.example                 # Environment variables template
├── .env                         # Your config (DO NOT COMMIT)
├── deploy.sh                    # Deployment helper script
├── init-ssl.sh                  # SSL certificate setup
├── README.md                    # This file
├── nginx/
│   ├── nginx.conf               # Main nginx config
│   └── conf.d/
│       ├── cdsconnect.conf      # Site config with SSL
│       └── cdsconnect-init.conf # Initial config for SSL setup
├── config/
│   ├── libraries/               # Your CQL/ELM libraries
│   └── hooks/                   # Your CDS Hooks configurations
└── .github/workflows/
    ├── docker-build-cql-services.yml    # CI workflow for CQL Services
    └── docker-build-authoring-tool.yml  # CI workflow for Authoring Tool
```

## GitHub Actions Setup

### For CQL Services Repository

1. Copy the workflow file to your fork:
   ```bash
   cp .github/workflows/docker-build-cql-services.yml \
      /path/to/AHRQ-CDS-Connect-CQL-SERVICES/.github/workflows/docker-build.yml
   ```

2. Enable GitHub Actions in repository settings

3. Push to trigger a build, or manually trigger via Actions tab

### For Authoring Tool Repository

1. Copy the workflow file to your fork:
   ```bash
   cp .github/workflows/docker-build-authoring-tool.yml \
      /path/to/AHRQ-CDS-Connect-Authoring-Tool/.github/workflows/docker-build.yml
   ```

2. Adjust Dockerfile paths based on repository structure

3. Enable GitHub Actions and push to trigger build

### Making Images Public (Optional)

By default, ghcr.io images are private. To make them public:

1. Go to: `https://github.com/orgs/iupui-soic/packages`
2. Click on each package
3. Go to Package settings → Change visibility → Public

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `DOMAIN` | Yes | Your domain (e.g., cdsconnect.org) |
| `LETSENCRYPT_EMAIL` | Yes | Email for Let's Encrypt notifications |
| `UMLS_API_KEY` | Yes | UMLS API key for VSAC downloads |
| `AUTH_SESSION_SECRET` | Yes | Secret for session encryption |
| `CQL_SERVICES_VERSION` | No | Image tag (default: latest) |
| `AUTHORING_TOOL_VERSION` | No | Image tag (default: latest) |

Generate a secure session secret:
```bash
openssl rand -hex 32
```

## Common Operations

### Update Images

```bash
# Pull latest images
docker-compose pull

# Restart with new images
docker-compose up -d
```

### Deploy Specific Version

```bash
# Edit .env
CQL_SERVICES_VERSION=v3.2.0
AUTHORING_TOOL_VERSION=v2.1.0

# Redeploy
docker-compose up -d
```

### View Logs

```bash
# All services
docker-compose logs -f

# Specific service
docker-compose logs -f cql-services
docker-compose logs -f authoring-api
```

### Backup MongoDB

```bash
# Create backup
docker-compose exec mongodb mongodump --out /data/db/backup

# Copy to host
docker cp cds-mongodb:/data/db/backup ./mongodb-backup-$(date +%Y%m%d)
```

### Renew SSL Certificates

Certificates auto-renew via certbot container. To force renewal:

```bash
docker-compose run --rm certbot renew --force-renewal
docker-compose restart nginx
```

## Troubleshooting

### Check Service Health

```bash
# Service status
docker-compose ps

# Health checks
curl -k https://localhost/health
curl -k https://localhost/cds-services
curl -k https://localhost/authoring/api/config
```

### Container Won't Start

```bash
# Check logs
docker-compose logs cql-services

# Check if image exists
docker images | grep cql-services

# Rebuild if needed
docker-compose build --no-cache cql-services
```

### SSL Issues

```bash
# Test certificate
openssl s_client -connect cdsconnect.org:443 -servername cdsconnect.org

# Check certbot logs
docker-compose logs certbot

# Re-run SSL setup
./init-ssl.sh
```

## Security Considerations

1. **Never commit `.env`** - Contains secrets
2. **Use specific image tags in production** - Not `latest`
3. **Enable HSTS** - Uncomment in nginx config after SSL confirmed working
4. **MongoDB authentication** - Consider enabling for production
5. **Firewall** - Only expose ports 80/443 externally
6. **Secrets rotation** - Periodically rotate `AUTH_SESSION_SECRET`