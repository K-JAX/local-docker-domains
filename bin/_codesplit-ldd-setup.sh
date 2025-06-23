#!/bin/bash

# example flow from this file
# bin/ldd-setup calls:
#orchestrator/setup-workflow.sh
#  ├── docker-integration/env-parser.sh      # Parse .env.local
#  ├── proxy-resolver/detector.sh            # Detect conflicts
#  ├── proxy-resolver/conflict-resolver.sh   # Choose strategy
#  ├── dependencies/*/install.sh             # Install tools
#  ├── dependencies/*/wrapper.sh             # Configure tools
#  └── orchestrator/validation.sh            # Validate setup


set -e  # exit on any error

# Source shared configuration
if [[ -f ".env.local" ]]; then
    source .env.local
else
    echo "Missing .env.local configuration file"
    exit 1
fi

# Utility function to discover all domain variables
# Returns an array of domain values from all *_DOMAIN environment variables
get_all_domains() {
    local domains=()
    while IFS='=' read -r name value; do
        # Check if variable name ends with _DOMAIN and has a non-empty value
        # Include PROJECT_DOMAIN only if it's assigned to a service variable
        if [[ "$name" =~ _DOMAIN$ ]] && [[ -n "$value" ]]; then
            # Skip PROJECT_DOMAIN itself, but allow service variables that use PROJECT_DOMAIN value
            if [[ "$name" == "PROJECT_DOMAIN" ]]; then
                continue
            fi
            
            # Remove quotes if present and add to array
            local clean_value=$(echo "$value" | sed 's/^["'\'']*//; s/["'\'']*$//')
            domains+=("$clean_value")
        fi
    done < <(env | grep '_DOMAIN=')
    
    # Output the domains array
    printf '%s\n' "${domains[@]}"
}

echo "Setting up ${PROJECT_TITLE} Development Environment..."

# check if running as root
if [[ $EUID -eq 0 ]]; then
   echo "Don't run this script with sudo. Run as: ./setup.sh"
   echo "   (The script will ask for sudo when needed)"
   exit 1
fi

# check prerequisites
command -v docker >/dev/null 2>&1 || { echo "Docker is required but not installed. Install Docker Desktop first."; exit 1; }
command -v brew >/dev/null 2>&1 || { echo "Homebrew is required but not installed. Install from https://brew.sh"; exit 1; }

echo "Prerequisites check passed"

# Run smart proxy detection and setup
echo "Running smart proxy detection..."

if [[ -x "./proxy-detection.sh" ]]; then
    if ./proxy-detection.sh; then
        echo ""
        echo "Smart proxy setup completed successfully!"
        echo ""
        echo "SSL certificates and proxy configuration are ready!"
        echo ""
        echo "Next steps to start your development environment:"
        echo "   1. Start containers:  docker compose up -d"
        echo "   2. View logs:         docker compose logs -f"
        echo "   3. Stop containers:   docker compose down"
        echo ""
        echo "Your sites will be available at:"
        # Display all configured domains dynamically
        while IFS= read -r domain; do
            echo "   • https://$domain"
        done < <(get_all_domains | sort)
        echo ""
        echo "Traefik dashboard: http://localhost:${TRAEFIK_DASHBOARD_PORT}"
        exit 0
    else
        echo "Smart proxy setup encountered issues, falling back to manual configuration..."
    fi
else
    echo "proxy-detection.sh not found or not executable, using fallback configuration..."
fi

echo ""
echo "Setting up fallback nginx-based proxy configuration..."

# Fallback to manual proxy setup (nginx-based)
echo "Installing mkcert for fallback setup..."
brew install mkcert 2>/dev/null || echo "mkcert already installed"

# create nginx proxies (directory and config)
echo "Creating proxy configuration..."
mkdir -p ./.local-proxy

cat > ./.local-proxy/nginx.conf << 'EOF'
events {
    worker_connections 1024;
}

http {
    server_tokens off;
    
    server {
        listen 80;
        server_name *.${PROJECT_DOMAIN};
        location / {
            proxy_pass http://host.docker.internal:${TRAEFIK_HTTP_PORT};
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
        }
    }
    
    server {
        listen 443 ssl;
        server_name *.${PROJECT_DOMAIN};
        ssl_certificate /certs/cert.pem;
        ssl_certificate_key /certs/key.pem;
        location / {
            proxy_pass https://host.docker.internal:${TRAEFIK_HTTPS_PORT};
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_ssl_verify off;
        }
    }
}
EOF


# edit the hosts file with local domains, requires lots of sudo work
manage_hosts() {
    local action="$1"
    local hosts_file="/etc/hosts"
    local marker_start="# ${PROJECT_TITLE} local development - START"
    local marker_end="# ${PROJECT_TITLE} local development - END"
    
    # Get all domains dynamically
    local domains=()
    while IFS= read -r domain; do
        domains+=("$domain")
    done < <(get_all_domains)
    
    if [[ ${#domains[@]} -eq 0 ]]; then
        echo "No *_DOMAIN variables found in configuration"
        return 1
    fi
    
    if [[ "$action" == "add" ]]; then
        # Check if already exists
        if grep -q "$marker_start" "$hosts_file" 2>/dev/null; then
            echo "${PROJECT_TITLE} domains already in /etc/hosts"
            return 0
        fi
        
        echo "Adding domains to /etc/hosts..."
        echo "Found ${#domains[@]} domain(s): ${domains[*]}"
        {
            echo ""
            echo "$marker_start"
            for domain in "${domains[@]}"; do
                echo "127.0.0.1 $domain"
            done
            echo "$marker_end"
        } | sudo tee -a "$hosts_file" > /dev/null
        echo "Added domains to /etc/hosts"
        
    elif [[ "$action" == "remove" ]]; then
        if grep -q "$marker_start" "$hosts_file" 2>/dev/null; then
            echo "Removing ${PROJECT_TITLE} domains from /etc/hosts..."
            sudo sed -i '' "/$marker_start/,/$marker_end/d" "$hosts_file"
            echo "Removed domains from /etc/hosts"
        fi
    fi
}

echo "Setting up local DNS resolution..."
manage_hosts "add"

echo "Installing SSL certificate authority..."
mkcert -install

echo "Creating required directories..."
mkdir -p ./.certs ./.traefik

echo "Generating SSL certificates..."
mkcert -key-file ./.certs/key.pem -cert-file ./.certs/cert.pem "*.${PROJECT_DOMAIN}"

# traefik certificate configuration
echo "Creating Traefik configuration..."
cat > ./.traefik/certificates.yml << 'EOF'
tls:
  stores:
    default:
      defaultCertificate:
        certFile: /certs/cert.pem
        keyFile: /certs/key.pem
  certificates:
    - certFile: /certs/cert.pem
      keyFile: /certs/key.pem
EOF

echo ""
echo "Fallback setup complete!"
echo ""
echo "SSL certificates and proxy configuration are ready!"
echo ""
echo "Next steps to start your development environment:"
echo "   1. Start containers:  docker compose up -d"
echo "   2. View logs:         docker compose logs -f"
echo "   3. Stop containers:   docker compose down"
echo ""
echo "Your sites will be available at:"
# Display all configured domains dynamically
while IFS= read -r domain; do
    echo "   • https://$domain"
done < <(get_all_domains | sort)
echo ""
echo "Traefik dashboard: http://localhost:${TRAEFIK_DASHBOARD_PORT}"
echo ""
echo "Note: Using fallback nginx proxy configuration"
echo "   If you resolve port conflicts later, try running ./proxy-detection.sh"