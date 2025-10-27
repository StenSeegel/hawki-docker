#!/bin/bash
set -e

# Show help function
show_help() {
    echo "HAWKI Docker Stop Script"
    echo ""
    echo "Usage: ./stop.sh --dev|--staging|--prod [--remove]"
    echo ""
    echo "Profiles:"
    echo "  --dev, --development   Stop development containers"
    echo "  --staging              Stop staging containers"
    echo "  --prod, --production   Stop production containers"
    echo ""
    echo "Options:"
    echo "  --remove               Also remove build volumes (forces rebuild)"
    echo "  --help, -h             Show this help message"
    echo ""
    echo "Examples:"
    echo "  ./stop.sh --dev"
    echo "  ./stop.sh --staging --remove"
    echo "  ./stop.sh --prod"
    echo ""
    echo "Note: Database volumes are NEVER removed automatically!"
    exit 0
}

# Default values
PROFILE=""
REMOVE_BUILD_VOLUMES=false

# Parse arguments
for arg in "$@"; do
    case $arg in
        --help|-h)
            show_help
            ;;
        --dev|--development)
            PROFILE="dev"
            ;;
        --staging)
            PROFILE="staging"
            ;;
        --prod|--production)
            PROFILE="prod"
            ;;
        --remove)
            REMOVE_BUILD_VOLUMES=true
            ;;
        *)
            echo "❌ Unknown argument: $arg"
            echo ""
            echo "Usage: ./stop.sh --dev|--staging|--prod [--remove]"
            echo ""
            echo "Options:"
            echo "  --dev          Stop development containers"
            echo "  --staging      Stop staging containers"
            echo "  --prod         Stop production containers"
            echo "  --remove       Also remove build volumes (forces rebuild)"
            echo "  --help, -h     Show help"
            exit 1
            ;;
    esac
done

# Check if profile is set
if [ -z "$PROFILE" ]; then
    echo "❌ Error: No profile specified!"
    echo ""
    echo "Usage: ./stop.sh --dev|--staging|--prod [--remove]"
    echo ""
    echo "Examples:"
    echo "  ./stop.sh --dev"
    echo "  ./stop.sh --staging --remove"
    echo "  ./stop.sh --prod"
    exit 1
fi

echo "🛑 Stopping HAWKI ${PROFILE^^} Containers..."
echo ""

# Stop containers
echo "⏸️  Stopping and removing containers..."
docker compose -f "docker-compose.${PROFILE}.yml" --env-file env/.env down

echo "✅ Containers stopped!"
echo ""

# Remove build volumes if requested
if [ "$REMOVE_BUILD_VOLUMES" = true ]; then
    echo "🗑️  Removing build volumes..."
    
    case $PROFILE in
        dev)
            docker volume rm docker_production_dev_vendor 2>/dev/null || echo "   ℹ️  Volume docker_production_dev_vendor not found"
            docker volume rm docker_production_dev_node_modules 2>/dev/null || echo "   ℹ️  Volume docker_production_dev_node_modules not found"
            ;;
        staging)
            docker volume rm docker_production_staging_public 2>/dev/null || echo "   ℹ️  Volume docker_production_staging_public not found"
            docker volume rm docker_production_staging_build 2>/dev/null || echo "   ℹ️  Volume docker_production_staging_build not found"
            ;;
        prod)
            docker volume rm docker_production_prod_public 2>/dev/null || echo "   ℹ️  Volume docker_production_prod_public not found"
            docker volume rm docker_production_prod_build 2>/dev/null || echo "   ℹ️  Volume docker_production_prod_build not found"
            ;;
    esac
    
    echo ""
    echo "✅ Build volumes removed! Next deployment will rebuild."
    echo ""
fi

echo "═══════════════════════════════════════════════════════"
echo "📋 Quick Reference:"
echo "   ./stop.sh --dev              # Stop development"
echo "   ./stop.sh --staging          # Stop staging"
echo "   ./stop.sh --prod             # Stop production"
echo "   ./stop.sh --staging --remove # Stop + rebuild frontend"
echo ""
echo "⚠️  Database volumes are NEVER removed automatically!"
echo "═══════════════════════════════════════════════════════"
