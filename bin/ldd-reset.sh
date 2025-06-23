#!/bin/bash

# bin/ldd-reset calls:
# orchestrator/reset-workflow.sh
#   ├── docker-integration/container-manager.sh  # Stop containers
#   ├── proxy-resolver/cleanup.sh               # Clean proxy configs
#   ├── dependencies/*/wrapper.sh               # Clean dependencies
#   └── orchestrator/status-reporter.sh         # Report cleanup

# Source shared configuration  
if [[ -f ".env.local" ]]; then
    source .env.local
else
    echo "Missing .env.local configuration file"
    exit 1
fi

# Parse command line arguments
FULL_RESET=false
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    echo "${PROJECT_TITLE} Reset Script"
    echo ""
    echo "Usage: ./reset.sh [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  (no args)     Standard reset - removes Docker containers, project dirs, and hosts entries"
    echo "  --full        Full reset - also removes HAProxy, nginx, SSL certificates, and optionally mkcert CA"
    echo "  --help, -h    Show this help message"
    echo ""
    echo "Examples:"
    echo "  ./reset.sh              # Standard reset"
    echo "  ./reset.sh --full       # Complete cleanup for fresh install"
    echo ""
    exit 0
elif [[ "$1" == "--full" ]]; then
    FULL_RESET=true
    echo "Performing FULL reset of ${PROJECT_TITLE} development environment..."
else
    echo "Resetting ${PROJECT_TITLE} development environment..."
fi

# Stop Docker services
echo "Stopping Docker services..."
docker compose down --volumes --remove-orphans 2>/dev/null || echo "Docker services already stopped or Docker not running"

# Remove project directories
echo "Removing project directories..."
rm -rf ./.certs ./.traefik ./.local-proxy

if [[ "$FULL_RESET" == "true" ]]; then
    echo "Performing full proxy cleanup..."
    
    # Stop and remove HAProxy
    echo "Stopping HAProxy processes..."
    sudo pkill -f haproxy 2>/dev/null || true
    
    # Stop any nginx processes that might be running from fallback
    echo "Stopping nginx processes..."
    sudo pkill -f nginx 2>/dev/null || true
    
    # Uninstall HAProxy if installed
    if command -v haproxy >/dev/null 2>&1; then
        echo "Uninstalling HAProxy..."
        brew uninstall haproxy 2>/dev/null || true
    fi
    
    # Remove HAProxy configuration files (check multiple possible locations)
    echo "Removing HAProxy configuration..."
    config_paths=(
        "/opt/homebrew/etc/haproxy.cfg"
        "/usr/local/etc/haproxy.cfg"
        "/etc/haproxy/haproxy.cfg"
    )
    
    for config_path in "${config_paths[@]}"; do
        if [[ -f "$config_path" ]]; then
            echo "   Removing $config_path"
            sudo rm -f "$config_path"*
        fi
    done
    
    # Clean up mkcert certificates and CA (optional - ask user)
    echo "Cleaning up SSL certificates..."
    if command -v mkcert >/dev/null 2>&1; then
        echo "Found mkcert installation. Removing project certificates..."
        # Remove just the project certs, keep the CA for other projects
        rm -f ./.certs/cert.pem ./.certs/key.pem 2>/dev/null || true
        
        # Check for multiple mkcert CAs that might cause conflicts
        ca_count=$(security find-certificate -a -c "mkcert" /Library/Keychains/System.keychain 2>/dev/null | grep -c "labl" || echo "0")
        if [[ "$ca_count" -gt 1 ]]; then
            echo "Found $ca_count mkcert CA certificates in system keychain"
            echo "   Multiple CAs can cause certificate trust issues"
            read -p "Clean up conflicting mkcert CAs? (recommended for fresh setup) (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                echo "Cleaning up mkcert CA conflicts..."
                mkcert -uninstall 2>/dev/null || true
                rm -rf "$(mkcert -CAROOT 2>/dev/null)" 2>/dev/null || true
                echo "mkcert CA conflicts cleaned up"
                echo "Note: You'll need to run setup again to create a fresh CA"
            fi
        fi
        
        # Optionally uninstall the CA root (ask user as this affects other projects)
        if [[ "$ca_count" -le 1 ]]; then
            read -p "Remove mkcert CA root certificates? This affects ALL local dev projects (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                echo "Uninstalling mkcert CA root..."
                mkcert -uninstall 2>/dev/null || true
                echo "Uninstalling mkcert..."
                brew uninstall mkcert 2>/dev/null || true
            fi
        fi
    fi
    
    # Clean up hosts file entries (both old and new format)
    echo "Cleaning up /etc/hosts entries..."
    project_upper=$(echo "${PROJECT_TITLE}" | tr '[:lower:]' '[:upper:]')
    
    # Remove new format entries
    sudo sed -i '' "/# === ${project_upper} DEV HOSTS START ===/,/# === ${project_upper} DEV HOSTS END ===/d" /etc/hosts 2>/dev/null || true
    
    # Remove old format entries (for backward compatibility)
    sudo sed -i '' "/# ${PROJECT_TITLE} local development - START/,/# ${PROJECT_TITLE} local development - END/d" /etc/hosts 2>/dev/null || true
    sudo sed -i '' "/# GetPosture local development - START/,/# GetPosture local development - END/d" /etc/hosts 2>/dev/null || true
    
    # Clean up any potential nginx configurations from fallback mode
    echo "Cleaning up nginx fallback configurations..."
    rm -rf ./.local-proxy/nginx.conf ./.local-proxy/nginx.pid 2>/dev/null || true
    
    # Check for any remaining processes on our ports
    echo "Checking for remaining processes listening on ports 80 and 443..."
    for port in 80 443; do
        listeners=$(lsof -i :$port 2>/dev/null | grep -E "TCP.*\*:(${port}|https|http).*\(LISTEN\)" || true)
        if [[ -n "$listeners" ]]; then
            echo "Found processes still listening on port $port:"
            echo "$listeners"
            echo "   You may need to stop them manually before running setup again."
        fi
    done
    
    echo "Full proxy cleanup completed"
else
    # Standard reset - only remove hosts file entries
    echo "Cleaning up /etc/hosts entries..."
    project_upper=$(echo "${PROJECT_TITLE}" | tr '[:lower:]' '[:upper:]')
    sudo sed -i '' "/# === ${project_upper} DEV HOSTS START ===/,/# === ${project_upper} DEV HOSTS END ===/d" /etc/hosts 2>/dev/null || true
    sudo sed -i '' "/# ${PROJECT_TITLE} local development - START/,/# ${PROJECT_TITLE} local development - END/d" /etc/hosts 2>/dev/null || true
fi

# Flush DNS cache
echo "Flushing DNS cache..."
sudo dscacheutil -flushcache 2>/dev/null || true

echo ""
if [[ "$FULL_RESET" == "true" ]]; then
    echo "Full reset complete! All proxy services, configurations, and certificates removed."
    echo "What was cleaned up:"
    echo "   • HAProxy proxy service and configuration"
    echo "   • nginx fallback configurations"
    echo "   • SSL certificates for this project"
    echo "   • /etc/hosts entries for local domains"
    echo "   • Project directories (.certs, .traefik, .local-proxy)"
    echo "   • DNS cache"
    echo ""
    echo "If you removed the mkcert CA root, you'll need to recreate it when setting up any local dev environment."
else
    echo "Reset complete! Use '--full' flag for complete proxy removal."
    echo "What was cleaned up:"
    echo "   • Docker containers and volumes"
    echo "   • Project directories (.certs, .traefik, .local-proxy)"
    echo "   • /etc/hosts entries for local domains"
    echo "   • DNS cache"
fi
echo ""
echo "Run './setup.sh' to start fresh."