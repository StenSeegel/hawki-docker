#!/bin/bash
# Shared deployment functions for HAWKI Docker deployments

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
            echo "✅ DOCKER.md updated from submodule"
        fi
        
        echo ""
    fi
}

# =====================================================
# Ensure docker config files exist in parent directory
# =====================================================
ensure_docker_configs_exist() {
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local parent_dir="$(dirname "$script_dir")"
    local source_dir="$script_dir"
    
    # Check and copy certs directory if needed
    if [ ! -d "$parent_dir/certs" ]; then
        echo "📋 First-time setup: Copying certs directory to project root..."
        cp -r "$source_dir/certs" "$parent_dir/certs"
        echo "✅ Certs directory copied"
    fi    
    echo "🔧 Checking docker configuration files..."
    
    # Check PHP config files
    if [ -d "$source_dir/php/config" ]; then
        mkdir -p "$parent_dir/docker/php/config"
        
        for file in "$source_dir/php/config"/*; do
            if [ -f "$file" ]; then
                local filename=$(basename "$file")
                local target="$parent_dir/docker/php/config/$filename"
                
                if [ ! -f "$target" ] || ! cmp -s "$file" "$target"; then
                    needs_copy=true
                    break
                fi
            fi
        done
    fi
    
    # Check Nginx config files
    if [ -d "$source_dir/nginx" ]; then
        mkdir -p "$parent_dir/docker/nginx/config"
        
        # Check for nginx.template.* files that need to be generated
        for template in "$source_dir/nginx/nginx.template."*; do
            if [ -f "$template" ]; then
                needs_copy=true
                break
            fi
        done
    fi
    
    # Copy files if needed
    if [ "$needs_copy" = true ]; then
        echo "📋 Copying docker configuration files from _docker to project root..."
        
        # Copy PHP config
        if [ -d "$source_dir/php/config" ]; then
            cp -r "$source_dir/php/config"/* "$parent_dir/docker/php/config/"
            echo "✅ PHP configuration copied to $parent_dir/docker/php/config/"
        fi
        
        # Copy PHP bin
        if [ -d "$source_dir/php/bin" ]; then
            mkdir -p "$parent_dir/docker/php/bin"
            cp -r "$source_dir/php/bin"/* "$parent_dir/docker/php/bin/"
            echo "✅ PHP bin scripts copied to $parent_dir/docker/php/bin/"
        fi
        
        # Copy PHP entrypoint scripts
        if [ -d "$source_dir/php" ]; then
            cp "$source_dir/php"/*.sh "$parent_dir/docker/php/" 2>/dev/null || true
            cp "$source_dir/php"/*.php "$parent_dir/docker/php/" 2>/dev/null || true
            echo "✅ PHP entrypoint scripts copied to $parent_dir/docker/php/"
        fi
        
        # Note: Nginx config is generated dynamically, but templates are managed here
        echo "ℹ️  Nginx config will be generated from templates"
        
        echo ""
    else
        echo "✅ Docker configuration files are up to date"
        echo ""
    fi
}

# =====================================================
# Clean up copied docker config files after build
# =====================================================
cleanup_docker_configs() {
    local parent_dir="$(cd .. && pwd)"
    
    echo "🧹 Cleaning up copied docker configuration files..."
    
    # Remove copied PHP config files
    if [ -d "$parent_dir/docker/php/config" ]; then
        rm -f "$parent_dir/docker/php/config"/*.ini
        rm -f "$parent_dir/docker/php/config/fpm-pool.conf"
        rm -f "$parent_dir/docker/php/config/supervisord.conf"
        echo "✅ Removed copied PHP config files"
    fi
    
    # Remove copied PHP scripts
    if [ -d "$parent_dir/docker/php" ]; then
        rm -f "$parent_dir/docker/php"/*.sh
        rm -f "$parent_dir/docker/php"/*.php
        echo "✅ Removed copied PHP entrypoint scripts"
    fi
    
    # Remove copied PHP bin
    if [ -d "$parent_dir/docker/php/bin" ]; then
        rm -rf "$parent_dir/docker/php/bin"/*
        echo "✅ Removed copied PHP bin scripts"
    fi
    
    # Note: We keep the Dockerfile in place as it might be needed for reference
    
    echo ""
}
