#!/bin/bash
set -e  # Exit on error

echo "🚀 Starting HAWKI Production Deployment (build from image)..."

# =====================================================
# Ensure Dockerfile exists in parent directory
# =====================================================
ensure_dockerfile_exists() {
    local parent_dir="$(cd .. && pwd)"
    local dockerfile_source="$(pwd)/dockerfile"
    
    if [ ! -d "$dockerfile_source" ] || [ ! -f "$dockerfile_source/Dockerfile" ]; then
        echo "❌ Error: dockerfile/Dockerfile not found in _docker directory!"
        exit 1
    fi
    
    if [ -f "$parent_dir/Dockerfile" ]; then
        # Check if files are different
        if ! cmp -s "$dockerfile_source/Dockerfile" "$parent_dir/Dockerfile"; then
            echo "⚠️  Dockerfile already exists in project root but differs from submodule version."
            echo ""
            read -p "Do you want to overwrite it with the version from _docker/dockerfile/? (yes/no): " -r
            echo
            if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
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

# Check if .env file exists
if [ ! -f ".env" ]; then
    echo "❌ Error: .env file not found in _docker directory!"
    echo "   Please create .env file from .env.example"
    exit 1
fi

# Generate nginx configuration from template
if [ -f "generate-nginx-config.sh" ]; then
    echo "🔧 Generating Nginx configuration..."
    ./generate-nginx-config.sh
fi

# Create external volumes if they don't exist
echo "🔧 Ensuring external volumes exist..."
if [ -f "scripts/create-volumes.sh" ]; then
    ./scripts/create-volumes.sh prod
else
    echo "❌ Error: scripts/create-volumes.sh not found!"
    exit 1
fi
echo ""

# Fix storage permissions for production (Linux only, skip on macOS)
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
        
        chmod -R 755 ./storage 2>/dev/null || true
        find ./storage -type f -exec chmod 644 {} \; 2>/dev/null || true
        echo "✅ Storage permissions set (UID:${STORAGE_UID}, GID:${STORAGE_GID})"
        echo ""
    else
        # Skipping storage permissions (not on Linux, Docker handles this)
        echo ""
    fi
fi

# Build from parent directory (where Dockerfile is located)
cd ..

# Load proxy configuration from .env file
if [ -f "_docker/.env" ]; then
    export HTTP_PROXY=$(grep -E "^DOCKER_HTTP_PROXY=" _docker/.env | cut -d '=' -f2- | tr -d '"' | tr -d "'")
    export HTTPS_PROXY=$(grep -E "^DOCKER_HTTPS_PROXY=" _docker/.env | cut -d '=' -f2- | tr -d '"' | tr -d "'")
    export NO_PROXY=$(grep -E "^DOCKER_NO_PROXY=" _docker/.env | cut -d '=' -f2- | tr -d '"' | tr -d "'")
    
    # Load VITE variables from .env
    export APP_NAME=$(grep -E "^APP_NAME=" _docker/.env | cut -d '=' -f2- | tr -d '"' | tr -d "'")
    export REVERB_APP_KEY=$(grep -E "^REVERB_APP_KEY=" _docker/.env | cut -d '=' -f2- | tr -d '"' | tr -d "'")
    export REVERB_HOST=$(grep -E "^REVERB_HOST=" _docker/.env | cut -d '=' -f2- | tr -d '"' | tr -d "'")
    export VITE_REVERB_HOST=$(grep -E "^VITE_REVERB_HOST=" _docker/.env | cut -d '=' -f2- | tr -d '"' | tr -d "'")
    export REVERB_PORT=$(grep -E "^REVERB_PORT=" _docker/.env | cut -d '=' -f2- | tr -d '"' | tr -d "'")
    export REVERB_SCHEME=$(grep -E "^REVERB_SCHEME=" _docker/.env | cut -d '=' -f2- | tr -d '"' | tr -d "'")
fi

# Set defaults for VITE variables
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
if [ -n "$HTTP_PROXY" ]; then
    echo "   Proxy: ${HTTP_PROXY}"
fi
echo ""

# Validate required VITE variables
if [ -z "$VITE_REVERB_HOST" ]; then
    echo "❌ ERROR: VITE_REVERB_HOST is not set!"
    echo ""
    echo "   Please set in _docker/.env:"
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

echo "🔨 Building app image..."
docker compose -f _docker/compose/docker-compose.prod.yml build \
  --no-cache --pull app

echo "🚢 Starting containers..."
docker compose -f _docker/compose/docker-compose.prod.yml up -d --force-recreate --remove-orphans

echo "⚙️  Running Laravel optimizations..."
docker compose -f _docker/compose/docker-compose.prod.yml exec app bash -c "php artisan migrate --force && \
    php artisan db:seed --force && \
    php artisan config:cache && \
    php artisan route:cache && \
    php artisan view:cache && \
    php artisan optimize:clear"

echo "📝 Updating system text keys..."
docker compose -f _docker/compose/docker-compose.prod.yml exec app php artisan texts:seed

echo "📝 Generating Git info..."
docker compose -f _docker/compose/docker-compose.prod.yml exec app bash -c "echo '[]' > /var/www/html/storage/app/test_users.json && git config --global --add safe.directory /var/www/html && /var/www/html/git_info.sh"

# Get APP_URL from .env file
cd _docker
APP_URL=$(grep -E "^APP_URL=" .env | cut -d '=' -f2- | tr -d '"' | tr -d "'")

echo ""
echo "✅ Production deployment complete!"
echo ""
if [ -n "$APP_URL" ]; then
    echo "🌐 Access your application at:"
    echo "   → $APP_URL"
else
    echo "🌐 Access your application at:"
    echo "   → http://localhost"
fi
echo ""
