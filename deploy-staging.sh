#!/bin/bash

# =====================================================
# HAWKI - Staging Deployment Script
# =====================================================
# Deploys HAWKI in staging mode with:
# - Custom build from repository
# - Debug mode enabled for testing
# - No Adminer (production-like setup)
# - Standard www-data user (no UID mapping)
#
# Usage:
#   ./deploy-staging.sh [--build] [--init]
#
# Options:
#   --build    Force rebuild of Docker images
#   --init     Force re-initialization of environment
# =====================================================

set -e  # Exit on error

# Load shared functions
source "$(dirname "$0")/.deploy-functions.sh"

echo "🚀 Starting HAWKI Staging Deployment..."
echo ""

# =====================================================
# Ensure Dockerfile exists in parent directory
# =====================================================
ensure_dockerfile_exists() {
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local parent_dir="$(dirname "$script_dir")"
    local dockerfile_source="$script_dir/dockerfile"
    
    if [ ! -d "$dockerfile_source" ] || [ ! -f "$dockerfile_source/Dockerfile" ]; then
        echo "❌ Error: dockerfile/Dockerfile not found in _docker directory!"
        exit 1
    fi
    
    if [ -f "$parent_dir/Dockerfile" ]; then
        # Check if files are different
        if ! cmp -s "$dockerfile_source/Dockerfile" "$parent_dir/Dockerfile"; then
            echo "⚠️  Dockerfile already exists in project root but differs from submodule version."
            echo ""
            read -p "Do you want to overwrite it with the version from _docker/dockerfile/? (y/n): " -r
            echo
            if [[ $REPLY =~ ^[Yy]([Ee][Ss])?$ ]]; then
                cp "$dockerfile_source/Dockerfile" "$parent_dir/Dockerfile"
                echo "✅ Dockerfile updated from submodule"
                
                # Also update DOCKER.md if it exists
                if [ -f "$dockerfile_source/DOCKER.md" ]; then
                    cp "$dockerfile_source/DOCKER.md" "$parent_dir/DOCKER.md"
                    echo "✅ DOCKER.md updated from submodule"
                fi
                echo ""
            else
                echo "ℹ️  Keeping existing Dockerfile in project root"
                echo ""
            fi
        fi
    else
        echo "📋 First-time setup: Copying Dockerfile to project root..."
        
        cp "$dockerfile_source/Dockerfile" "$parent_dir/Dockerfile"
        echo "✅ Dockerfile copied to $parent_dir/Dockerfile"
        
        # Also copy DOCKER.md if it exists (optional documentation)
        if [ -f "$dockerfile_source/DOCKER.md" ]; then
            cp "$dockerfile_source/DOCKER.md" "$parent_dir/DOCKER.md"
            echo "✅ DOCKER.md copied to $parent_dir/DOCKER.md"
        fi
        
        echo ""
    fi
}

# Check and copy Dockerfile if needed
ensure_dockerfile_exists

# Check and copy docker configs if needed
ensure_docker_configs_exist

# Stop any running dev/prod containers first (they use the same ports)
if docker ps --format '{{.Names}}' | grep -qE '^hawki-(dev|prod)-'; then
    echo "⚠️  Detected running dev/prod containers. Stopping them first..."
    echo ""
    
    # Stop dev containers if running
    if docker ps --format '{{.Names}}' | grep -q '^hawki-dev-'; then
        echo "🛑 Stopping dev containers..."
        cd ..
        docker compose -f _docker/compose/docker-compose.dev.yml stop 2>/dev/null || true
        cd _docker
        echo "✅ Dev containers stopped"
        echo ""
    fi
    
    # Stop prod containers if running
    if docker ps --format '{{.Names}}' | grep -q '^hawki-prod-'; then
        echo "🛑 Stopping prod containers..."
        cd ..
        docker compose -f _docker/compose/docker-compose.prod.yml stop 2>/dev/null || true
        cd _docker
        echo "✅ Prod containers stopped"
        echo ""
    fi
fi

# Parse arguments
FORCE_BUILD=false
FORCE_INIT=false
for arg in "$@"; do
    case $arg in
        --build)
            FORCE_BUILD=true
            ;;
        --init)
            FORCE_INIT=true
            ;;
    esac
done

# Initialize environment if .env doesn't exist or --init flag is set
if [ ! -f "env/.env" ] || [ "$FORCE_INIT" = true ]; then
    echo "🔧 Initializing environment..."
    if [ -f "env/env-init.sh" ]; then
        DEPLOY_PROFILE=staging ./env/env-init.sh ${FORCE_INIT:+--force}
    else
        echo "❌ Error: env/env-init.sh not found!"
        exit 1
    fi
    echo ""
fi

# Load environment variables
# Load order matters: .env.staging first (defaults), then .env (user overrides)
if [ -f "env/.env.staging" ]; then
    set -a
    source env/.env.staging
    set +a
fi

if [ -f "env/.env" ]; then
    set -a
    source env/.env
    set +a
fi

# Export profile for docker-compose
export PROJECT_NAME=${PROJECT_NAME:-hawki-staging}
export PROJECT_HAWKI_IMAGE=${PROJECT_HAWKI_IMAGE:-hawki:staging}
export DEPLOY_PROFILE=staging  # Set profile for nginx config generation

# Generate nginx configuration
echo "🔧 Generating Nginx configuration..."
if [ -f "nginx/generate-nginx-config.sh" ]; then
    ./nginx/generate-nginx-config.sh
else
    echo "⚠️  Warning: nginx/generate-nginx-config.sh not found"
fi
echo ""

# Create external volumes if they don't exist
echo "🔧 Ensuring external volumes exist..."
if [ -f "scripts/create-volumes.sh" ]; then
    ./scripts/create-volumes.sh staging
else
    echo "❌ Error: scripts/create-volumes.sh not found!"
    exit 1
fi
echo ""

# Fix storage permissions for staging (Linux only, skip on macOS)
if [ -d "./storage" ]; then
    # Check if running on Linux (where permissions are critical for Docker)
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        echo "📁 Setting storage ownership and permissions (Linux)..."
        STORAGE_UID=${DOCKER_UID:-33}
        STORAGE_GID=${DOCKER_GID:-33}
        
        # Use sudo only if not root
        if [ "$EUID" -ne 0 ]; then
            sudo chown -R ${STORAGE_UID}:${STORAGE_GID} ./storage 2>/dev/null || true
        else
            chown -R ${STORAGE_UID}:${STORAGE_GID} ./storage 2>/dev/null || true
        fi
        
        chmod -R 775 ./storage 2>/dev/null || true
        find ./storage -type f -exec chmod 664 {} \; 2>/dev/null || true
        echo "✅ Storage permissions set (UID:${STORAGE_UID}, GID:${STORAGE_GID})"
        echo ""
    else
        # Skipping storage permissions (not on Linux, Docker handles this)
        echo ""
    fi
fi

# Build from parent directory (where Dockerfile is located)
cd ..

# Export all build args BEFORE any build commands
# Export proxy configuration
export HTTP_PROXY="$DOCKER_HTTP_PROXY"
export HTTPS_PROXY="$DOCKER_HTTPS_PROXY"
export NO_PROXY="$DOCKER_NO_PROXY"

# Export VITE variables for frontend build
export VITE_APP_NAME="${APP_NAME:-HAWKI2}"
export VITE_REVERB_APP_KEY="${REVERB_APP_KEY}"
export VITE_REVERB_HOST="${VITE_REVERB_HOST:-$REVERB_HOST}"
export VITE_REVERB_PORT="${REVERB_PORT:-443}"
export VITE_REVERB_SCHEME="${REVERB_SCHEME:-https}"

echo ""
echo "🔧 Build configuration:"
echo "   VITE_REVERB_HOST: ${VITE_REVERB_HOST}"
echo "   VITE_REVERB_PORT: ${VITE_REVERB_PORT}"
echo "   VITE_REVERB_SCHEME: ${VITE_REVERB_SCHEME}"
if [ -n "$DOCKER_HTTP_PROXY" ]; then
    echo "   Proxy: ${DOCKER_HTTP_PROXY}"
fi
echo ""

# Validate required VITE variables
if [ -z "$VITE_REVERB_HOST" ]; then
    echo "❌ ERROR: VITE_REVERB_HOST is not set!"
    echo ""
    echo "   Please run: cd env && ./env-init.sh --profile=staging"
    echo "   Or manually set in env/.env:"
    echo "     REVERB_HOST=your-domain.com"
    echo "     VITE_REVERB_HOST=your-domain.com"
    echo ""
    exit 1
fi

if [ -z "$VITE_REVERB_APP_KEY" ]; then
    echo "⚠️  WARNING: REVERB_APP_KEY is not set!"
    echo "   WebSocket authentication may not work properly."
    echo ""
fi

# Check if image exists, if not, force build
if ! docker image inspect "$PROJECT_HAWKI_IMAGE" >/dev/null 2>&1; then
    echo "📦 Image $PROJECT_HAWKI_IMAGE not found, building automatically..."
    FORCE_BUILD=true
fi

if [ "$FORCE_BUILD" = true ]; then
    echo "🔨 Building Docker images from repository..."
    
    # Remove containers completely to release volume locks
    echo "🛑 Removing existing containers (preserving database & user uploads)..."
    docker compose -f _docker/compose/docker-compose.staging.yml down
    
    # ONLY remove staging_build volume (NOT staging_public with user uploads!)
    echo "🗑️  Removing old build assets volume (preserving database & user uploads)..."
    VOLUME_NAME="${PROJECT_NAME}_staging_build"
    if docker volume inspect "$VOLUME_NAME" >/dev/null 2>&1; then
        docker volume rm "$VOLUME_NAME" 2>/dev/null || {
            echo "⚠️  Could not remove volume $VOLUME_NAME (might still be in use)"
            echo "   Please check: docker ps -a | grep staging"
        }
    else
        echo "   Volume $VOLUME_NAME does not exist, skipping..."
    fi
    
    # Generate cache bust value to force frontend rebuild
    CACHEBUST=$(date +%s)
    echo "🔄 Cache bust: $CACHEBUST"
    
    docker compose -f _docker/compose/docker-compose.staging.yml build \
      --pull \
      --build-arg CACHEBUST=$CACHEBUST \
      app
    echo ""
    
    # Clean up copied config files after successful build
    cd _docker
    cleanup_docker_configs
    cd ..
fi

# Prepare proxy args for docker compose up --build
if [ -n "$DOCKER_HTTP_PROXY" ]; then
    COMPOSE_BUILD_ARGS="--build-arg HTTP_PROXY=$DOCKER_HTTP_PROXY --build-arg HTTPS_PROXY=$DOCKER_HTTPS_PROXY --build-arg NO_PROXY=$DOCKER_NO_PROXY"
else
    COMPOSE_BUILD_ARGS=""
fi

echo "🚢 Starting containers..."
# Don't use --build here, we already built above!
docker compose -f _docker/compose/docker-compose.staging.yml up -d --remove-orphans

# Wait for containers to be ready
echo "⏳ Waiting for containers to be ready..."
sleep 10
echo ""

# Run Laravel setup (without route:cache due to Laravel 12 bug)
echo "⚙️  Running Laravel setup..."
docker compose -f _docker/compose/docker-compose.staging.yml exec app bash -c "\
    php artisan migrate --force && \
    php artisan db:seed --force && \
    php artisan storage:link && \
    php artisan config:cache && \
    php artisan view:cache && \
    php artisan optimize:clear"
echo ""

# Update system texts with new keys
echo "📝 Updating system text keys..."
docker compose -f _docker/compose/docker-compose.staging.yml exec app php artisan texts:seed
echo ""

# Fix storage permissions inside container
echo "🔒 Setting storage permissions inside container..."
docker compose -f _docker/compose/docker-compose.staging.yml exec app bash -c "\
    chmod -R 775 storage && \
    chmod -R 775 storage/logs && \
    chown -R www-data:www-data storage"
echo ""

# Generate git info
echo "📝 Generating Git info..."
docker compose -f _docker/compose/docker-compose.staging.yml exec app bash -c "\
    git config --global --add safe.directory /var/www/html && \
    /var/www/html/git_info.sh" 2>/dev/null || true
echo ""

# Display success message
cd _docker
APP_URL=${APP_URL:-https://staging.hawki.test}

echo "═══════════════════════════════════════════════════════"
echo "✅ Staging deployment complete!"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "🌐 Access your application:"
echo "   → $APP_URL"
echo ""
echo "💡 Staging Features:"
echo "   → Built from current repository code"
echo "   → Debug mode enabled for testing"
echo "   → Production-like setup (no Adminer)"
echo "   → Cached routes and config for performance"
echo "   → Standard www-data user permissions"
echo ""
echo "🔄 Quick Commands:"
echo "   View logs:           docker compose logs -f app"
echo "   Restart containers:  docker compose restart"
echo "   Force rebuild:       ./deploy-staging.sh --build"
echo "   Reinitialize env:    ./deploy-staging.sh --init"
echo ""
echo "═══════════════════════════════════════════════════════"
