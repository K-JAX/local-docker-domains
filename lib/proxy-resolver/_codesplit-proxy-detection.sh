#!/bin/bash
set -e

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

# Utility function to get domain variable names and values
# Returns name=value pairs for all *_DOMAIN variables
get_domain_vars() {
    while IFS='=' read -r name value; do
        if [[ "$name" =~ _DOMAIN$ ]] && [[ -n "$value" ]]; then
            local clean_value=$(echo "$value" | sed 's/^["'\'']*//; s/["'\'']*$//')
            echo "${name}=${clean_value}"
        fi
    done < <(env | grep '_DOMAIN=')
}

echo "Detecting local development environment for ${PROJECT_TITLE}..."

check_port() {
    local port=$1
    # Look for TCP *:port (LISTEN) or TCP *:service (LISTEN) patterns
    if lsof -i :$port 2>/dev/null | grep -E "TCP.*\*:(${port}|https|http).*\(LISTEN\)" &> /dev/null; then
        return 0  # Port has a TCP listener
    else
        return 1  # Port is free for TCP listening
    fi
}

# Function to get process using port (TCP LISTENING only)  
get_port_process() {
    local port=$1
    # Get processes with specific LISTEN pattern
    lsof -i :$port 2>/dev/null | grep -E "TCP.*\*:(${port}|https|http).*\(LISTEN\)" | awk '{print $1}' | head -1
}
# Function to detect OS
detect_os() {
    case "$(uname -s)" in
        Darwin) echo "macos" ;;
        Linux)  echo "linux" ;;
        CYGWIN*|MINGW*|MSYS*) echo "windows" ;;
        *) echo "unknown" ;;
    esac
}

# Check for Laravel Valet
check_valet() {
    if command -v valet &> /dev/null; then
        if valet status 2>/dev/null | grep -q "running"; then
            echo "Laravel Valet detected and running"
            echo ""
            echo "Valet can conflict with our proxy setup. We have two options:"
            echo "1. Try to configure Valet to work with our domains (experimental)"
            echo "2. Stop Valet and use HAProxy (recommended, more reliable)"
            echo ""
            read -p "Stop Valet and use HAProxy instead? [Y/n]: " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Nn]$ ]]; then
                echo "Proceeding with Valet integration (experimental)..."
                setup_valet_proxy
                return 0
            else
                echo "Stopping Valet services to use HAProxy..."
                if stop_valet_services; then
                    echo "Valet stopped successfully. Proceeding with HAProxy setup..."
                    return 1  # Continue to HAProxy setup
                else
                    echo "Failed to stop Valet services. Please stop manually:"
                    echo "  sudo brew services stop nginx"
                    echo "  sudo brew services stop dnsmasq"
                    echo "Then run this script again."
                    exit 1
                fi
            fi
        else
            echo "Laravel Valet installed but not running"
        fi
    fi
    return 1
}

# Check for Local by Flywheel
check_local_flywheel() {
    local os=$(detect_os)
    local app_path=""
    
    case $os in
        "macos")
            app_path="/Applications/Local.app"
            process_pattern="Local.app\|getflywheel\|local-lightning"
            ;;
        "linux")
            app_path="/opt/Local"
            process_pattern="local-by-flywheel\|getflywheel"
            ;;
    esac
    
    if [[ -d "$app_path" ]]; then
        if pgrep -f "$process_pattern" &> /dev/null; then
            echo "Local by Flywheel detected and running"
            echo "Local by Flywheel may conflict with ports 80/443"
            echo "    Consider stopping Local or using different ports"
            return 0
        else
            echo "Local by Flywheel installed but not running"
            return 1  # Not running, so no conflict
        fi
    fi
    return 1
}

# Check for MAMP/XAMPP
check_mamp_xampp() {
    if pgrep -f "MAMP\|XAMPP" &> /dev/null; then
        echo "MAMP/XAMPP detected and running"
        echo "MAMP/XAMPP may conflict with ports 80/443"
        echo "    Consider stopping MAMP/XAMPP or using different ports"
        return 0
    fi
    return 1
}

# Check for existing nginx
check_existing_nginx() {
    if pgrep -f "nginx" &> /dev/null; then
        echo "nginx process detected"
        
        # Try to find nginx config location
        local nginx_conf=""
        if [[ -f "/usr/local/etc/nginx/nginx.conf" ]]; then
            nginx_conf="/usr/local/etc/nginx/nginx.conf"
        elif [[ -f "/etc/nginx/nginx.conf" ]]; then
            nginx_conf="/etc/nginx/nginx.conf"
        fi
        
        if [[ -n "$nginx_conf" ]]; then
            echo "Found nginx config at: $nginx_conf"
            setup_nginx_proxy "$nginx_conf"
            return 0
        else
            echo "nginx running but config location unknown"
        fi
    fi
    return 1
}

# Check for existing Apache
check_existing_apache() {
    if pgrep -f "apache\|httpd" &> /dev/null; then
        echo "Apache/httpd process detected"
        echo "Apache may conflict with ports 80/443"
        echo "    Consider adding virtual hosts or stopping Apache"
        return 0
    fi
    return 1
}

# Check port availability
check_port_availability() {
    local port80_free=true
    local port443_free=true
    local port80_process=""
    local port443_process=""
    
    if check_port 80; then
        port80_free=false
        port80_process=$(get_port_process 80)
    fi
    
    if check_port 443; then
        port443_free=false
        port443_process=$(get_port_process 443)
    fi
    
    if [[ "$port80_free" == false ]] || [[ "$port443_free" == false ]]; then
        echo "Required ports are in use:"
        [[ "$port80_free" == false ]] && echo "    Port 80: $port80_process"
        [[ "$port443_free" == false ]] && echo "    Port 443: $port443_process"
        echo ""
        echo "Options:"
        echo "1. Stop the conflicting services"
        echo "2. Use custom ports in URLs (e.g., :18080)"
        echo "3. Configure the existing service to proxy your domains"
        return 1
    else
        echo "Ports 80 and 443 are available"
        return 0
    fi
}

# Setup functions (to be implemented)
setup_valet_proxy() {
    echo "Setting up Laravel Valet proxy..."
    
    local valet_config_dir="$HOME/.config/valet/Nginx"
    local config_file="$valet_config_dir/${PROJECT_TITLE}.conf"
    
    # Create config directory if it doesn't exist
    mkdir -p "$valet_config_dir"
    
    echo "Creating nginx config for ${PROJECT_TITLE} domains..."
    
    # Get all domains dynamically
    local domains=()
    while IFS= read -r domain; do
        domains+=("$domain")
    done < <(get_all_domains)
    
    if [[ ${#domains[@]} -eq 0 ]]; then
        echo "Warning: No *_DOMAIN variables found in configuration"
        return 1
    fi
    
    echo "Found ${#domains[@]} domain(s): ${domains[*]}"
    
    # Create nginx server blocks for each domain
    cat > "$config_file" << EOF
# ${PROJECT_TITLE} development domains
# Auto-generated by proxy-detection.sh - do not edit manually
# Generated on: $(date)

EOF
    
    # Create the certificate paths
    local cert_dir="$(pwd)/.certs"
    
    for domain in "${domains[@]}"; do
        cat >> "$config_file" << EOF
# HTTP server block for $domain
server {
    listen 80;
    server_name $domain;
    
    location / {
        proxy_pass http://127.0.0.1:${TRAEFIK_HTTP_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}

# HTTPS server block for $domain  
server {
    listen 443 ssl;
    http2 on;
    server_name $domain;
    
    ssl_certificate "$cert_dir/cert.pem";
    ssl_certificate_key "$cert_dir/key.pem";
    
    location / {
        proxy_pass https://127.0.0.1:${TRAEFIK_HTTPS_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_ssl_verify off;
    }
}

EOF
    done
    
    echo "Created nginx config at: $config_file"
    
    # Setup SSL certificates using our existing mkcert setup
    echo "Setting up SSL certificates..."
    setup_ssl_certificates
    
    # Setup hosts file entries
    setup_hosts_file
    
    # Restart Valet to pick up new config
    echo "Restarting Valet to apply configuration..."
    if valet restart; then
        echo "Valet restarted successfully"
        echo ""
        echo "Setup complete! Your development environment is ready."
        echo ""
        echo "Next steps:"
        echo "   1. Run: docker compose up -d"
        echo "   2. Access your sites:"
        
        # Display all configured domains dynamically
        for domain in "${domains[@]}"; do
            echo "      • https://$domain"
        done
        
        echo "   3. HTTP requests will automatically redirect to HTTPS"
        echo ""
        echo "To remove this setup later:"
        echo "   rm $config_file && valet restart"
        return 0
    else
        echo "Error: Failed to restart Valet"
        return 1
    fi
}

setup_nginx_proxy() {
    local config_path=$1
    echo "Setting up nginx proxy at $config_path..."
    
    # Get all domains dynamically
    local domains=()
    while IFS= read -r domain; do
        domains+=("$domain")
    done < <(get_all_domains)
    
    if [[ ${#domains[@]} -eq 0 ]]; then
        echo "Warning: No *_DOMAIN variables found in configuration"
        return 1
    fi
    
    echo "Found ${#domains[@]} domain(s): ${domains[*]}"
    
    # Backup existing config
    if [[ -f "$config_path" ]]; then
        sudo cp "$config_path" "${config_path}.backup.$(date +%Y%m%d_%H%M%S)"
        echo "Backed up existing nginx config"
    fi
    
    # Determine config directory for includes
    local config_dir=$(dirname "$config_path")
    local include_file="$config_dir/${PROJECT_TITLE}_proxy.conf"
    
    # Create include file with our server blocks
    echo "Creating nginx proxy configuration..."
    local cert_dir="$(pwd)/.certs"
    
    sudo tee "$include_file" > /dev/null << EOF
# ${PROJECT_TITLE} development domains
# Auto-generated by proxy-detection.sh - do not edit manually
# Generated on: $(date)

EOF
    
    for domain in "${domains[@]}"; do
        sudo tee -a "$include_file" > /dev/null << EOF
# HTTP server block for $domain
server {
    listen 80;
    server_name $domain;
    
    location / {
        proxy_pass http://127.0.0.1:${TRAEFIK_HTTP_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}

# HTTPS server block for $domain
server {
    listen 443 ssl;
    http2 on;
    server_name $domain;
    
    ssl_certificate "$cert_dir/cert.pem";
    ssl_certificate_key "$cert_dir/key.pem";
    
    location / {
        proxy_pass https://127.0.0.1:${TRAEFIK_HTTPS_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_ssl_verify off;
    }
}

EOF
    done
    
    # Add include directive to main nginx config if not present
    if ! sudo grep -q "include.*${PROJECT_TITLE}_proxy.conf" "$config_path" 2>/dev/null; then
        echo "Adding include directive to main nginx config..."
        
        # Add include directive inside http block
        sudo sed -i.bak "/^http {/a\\
    include $include_file;
" "$config_path"
    fi
    
    echo "Created nginx proxy config at: $include_file"
    
    # Test nginx configuration
    if sudo nginx -t; then
        echo "Nginx configuration test passed"
        if sudo nginx -s reload; then
            echo "Nginx reloaded successfully"
            setup_hosts_file
            echo ""
            echo "Setup complete! Your development environment is ready."
            echo ""
            echo "Next steps:"
            echo "   1. Run: docker compose up -d"
            echo "   2. Access your sites:"
            
            # Display all configured domains dynamically
            for domain in "${domains[@]}"; do
                echo "      • https://$domain"
            done
            
            echo "   3. HTTP requests will automatically redirect to HTTPS"
            echo ""
            echo "To remove this setup later:"
            echo "   sudo rm $include_file && sudo nginx -s reload"
            return 0
        else
            echo "Error: Failed to reload nginx"
            return 1
        fi
    else
        echo "Error: Nginx configuration test failed"
        sudo rm "$include_file" 2>/dev/null
        return 1
    fi
}

setup_haproxy() {
    echo "Setting up HAProxy as local development proxy..."
    
    local os=$(detect_os)
    
    # Install HAProxy if needed
    if ! command -v haproxy &> /dev/null; then
        echo "Installing HAProxy..."
        case $os in
            "macos")
                brew install haproxy
                ;;
            "linux")
                if command -v apt &> /dev/null; then
                    sudo apt update && sudo apt install -y haproxy
                elif command -v yum &> /dev/null; then
                    sudo yum install -y haproxy
                elif command -v dnf &> /dev/null; then
                    sudo dnf install -y haproxy
                fi
                ;;
        esac
    else
        echo "HAProxy already installed"
    fi
    
    # Setup SSL certificates
    setup_ssl_certificates
    
    # Setup hosts file entries
    setup_hosts_file
    
    # Create config 
    echo "📝 Creating HAProxy configuration..."
    if create_haproxy_config; then
        # Determine the config path (same logic as in create_haproxy_config)
        local config_path=""
        case $os in
            "macos")
                if [[ -d "/opt/homebrew" ]]; then
                    config_path="/opt/homebrew/etc/haproxy.cfg"
                elif [[ -d "/usr/local/Homebrew" ]] || [[ -d "/usr/local/etc" ]]; then
                    config_path="/usr/local/etc/haproxy/haproxy.cfg"
                fi
                ;;
            "linux")
                config_path="/etc/haproxy/haproxy.cfg"
                ;;
        esac
        
        if [[ -n "$config_path" ]] && [[ -f "$config_path" ]]; then
            echo "✅ HAProxy config created at: $config_path"
            # Start HAProxy with the correct config path
            start_haproxy "$os" "$config_path"
        else
            echo "❌ HAProxy config file not found at: $config_path"
            return 1
        fi
    else
        echo "❌ Failed to create HAProxy config"
        return 1
    fi
}

setup_ssl_certificates() {
    echo "Setting up SSL certificates with mkcert..."
    
    # Install mkcert if needed
    if ! command -v mkcert &> /dev/null; then
        echo "Installing mkcert..."
        case $(detect_os) in
            "macos")
                brew install mkcert
                ;;
            "linux")
                # Download mkcert binary
                curl -JLO "https://dl.filippo.io/mkcert/latest?for=linux/amd64"
                chmod +x mkcert-v*-linux-amd64
                sudo mv mkcert-v*-linux-amd64 /usr/local/bin/mkcert
                ;;
        esac
    else
        echo "mkcert already installed"
    fi
    
    # Install the local CA
    echo "Installing mkcert root CA..."
    mkcert -install
    
    # Create certificates directory
    local cert_dir="$(pwd)/.certs"
    mkdir -p "$cert_dir"
    
    # Generate certificates with local mkcert (not Docker)
    echo "Generating certificates for *.${PROJECT_DOMAIN}..."
    mkcert -key-file "$cert_dir/key.pem" -cert-file "$cert_dir/cert.pem" "*.${PROJECT_DOMAIN}"
    
    echo "SSL certificates generated in $cert_dir"
    
    # Create Traefik dynamic configuration for certificates
    echo "Creating Traefik certificate configuration..."
    local traefik_dir="$(pwd)/.traefik"
    mkdir -p "$traefik_dir"
    
    cat > "$traefik_dir/certificates.yml" << EOF
tls:
  certificates:
    - certFile: /certs/cert.pem
      keyFile: /certs/key.pem
      stores:
        - default
  stores:
    default:
      defaultCertificate:
        certFile: /certs/cert.pem
        keyFile: /certs/key.pem
EOF
    
    echo "Traefik certificate configuration created"
    echo "Note: Certificates generated with local mkcert CA for browser trust"
}

create_haproxy_config() {
    local config_path=""
    local os=$(detect_os)
    
    echo "Determining HAProxy config location..."
    
    case $os in
        "macos")
            # Detect actual Homebrew installation path
            if [[ -d "/opt/homebrew" ]]; then
                # Apple Silicon Mac or newer Homebrew
                config_path="/opt/homebrew/etc/haproxy.cfg"
                config_dir="/opt/homebrew/etc"
            elif [[ -d "/usr/local/Homebrew" ]] || [[ -d "/usr/local/etc" ]]; then
                # Intel Mac or older Homebrew  
                config_path="/usr/local/etc/haproxy/haproxy.cfg"
                config_dir="/usr/local/etc/haproxy"
            else
                echo "Could not detect Homebrew installation path"
                return 1
            fi
            ;;
        "linux")
            config_path="/etc/haproxy/haproxy.cfg"
            config_dir="/etc/haproxy"
            ;;
    esac
    
    echo "Using config path: $config_path"
    
    # Create config directory if it doesn't exist
    if [[ ! -d "$config_dir" ]]; then
        echo "Creating config directory: $config_dir"
        sudo mkdir -p "$config_dir"
    fi
     # Define markers using environment variables
    local project_upper=$(echo "${PROJECT_TITLE}" | tr '[:lower:]' '[:upper:]')
    local proxy_start_marker="# === ${project_upper} DEV PROXY START ==="
    local proxy_end_marker="# === ${project_upper} DEV PROXY END ==="
    
    # Check if our configuration already exists
    if [[ -f "$config_path" ]] && grep -q "$proxy_start_marker" "$config_path"; then
        echo "${PROJECT_TITLE} configuration already exists in HAProxy config"
        echo "Removing existing configuration..."
        remove_haproxy_config "$config_path"
    fi

    # Backup existing config if it exists and doesn't have our markers
    if [[ -f "$config_path" ]] && ! grep -q "$proxy_start_marker" "$config_path"; then
        echo "Backing up existing HAProxy config to ${config_path}.backup"
        sudo cp "$config_path" "${config_path}.backup"
    fi
    
    # Create or update the config file with marked sections
    echo "Creating HAProxy config at $config_path"
    
    sudo tee "$config_path" > /dev/null << EOF
$proxy_start_marker
# This section is managed by ${PROJECT_TITLE} proxy-detection.sh
# Do not edit manually - changes will be overwritten
# Generated on: $(date)

global
    daemon
    maxconn 256

defaults
    mode tcp
    timeout connect 5000ms
    timeout client 50000ms
    timeout server 50000ms

# HTTP Frontend (port ${HAPROXY_HTTP_PORT})
frontend http_frontend
    mode http
    bind *:${HAPROXY_HTTP_PORT}
    
    # Route by hostname for HTTP
    acl is_${PROJECT_TITLE} hdr(host) -m sub ${PROJECT_DOMAIN%.*}
    use_backend ${PROJECT_TITLE}_http if is_${PROJECT_TITLE}
    default_backend ${PROJECT_TITLE}_http

# HTTPS Frontend (port ${HAPROXY_HTTPS_PORT}) - TCP mode for SSL passthrough
frontend https_frontend
    mode tcp
    bind *:${HAPROXY_HTTPS_PORT}
    
    # Since we're doing SSL passthrough, we don't inspect SNI
    # Just forward all HTTPS traffic to Traefik
    default_backend ${PROJECT_TITLE}_https

backend ${PROJECT_TITLE}_http
    mode http
    balance roundrobin
    server traefik 127.0.0.1:${TRAEFIK_HTTP_PORT}

backend ${PROJECT_TITLE}_https
    mode tcp
    balance roundrobin
    server traefik 127.0.0.1:${TRAEFIK_HTTPS_PORT}

$proxy_end_marker
EOF

    echo "HAProxy config created at $config_path"
    echo "Key configuration details:"
    echo "   - HTTP (port 80) routes to Traefik at 127.0.0.1:18080"
    echo "   - HTTPS (port 443) uses TCP passthrough to 127.0.0.1:18443" 
    echo "   - SSL certificates are handled by Traefik, not HAProxy"
    echo "   - Configuration is marked for easy removal/updates"
}

remove_haproxy_config() {
    local config_path=$1
    local project_upper=$(echo "${PROJECT_TITLE}" | tr '[:lower:]' '[:upper:]')
    local proxy_start_marker="# === ${project_upper} DEV PROXY START ==="
    local proxy_end_marker="# === ${project_upper} DEV PROXY END ==="
    
    echo "Removing ${PROJECT_TITLE} configuration from HAProxy..."
    
    if [[ -f "$config_path" ]]; then
        # Create a temporary file without our configuration
        sudo awk -v start="$proxy_start_marker" -v end="$proxy_end_marker" '
            $0 == start { skip=1; next }
            $0 == end { skip=0; next }
            !skip { print }
        ' "$config_path" > /tmp/haproxy_cleaned.cfg
        
        # Replace the original with the cleaned version
        sudo mv /tmp/haproxy_cleaned.cfg "$config_path"
        echo "${PROJECT_TITLE} configuration removed from HAProxy"
    else
        echo "HAProxy config file not found at $config_path"
    fi
}

cleanup_haproxy() {
    echo "Cleaning up HAProxy setup..."
    
    local os=$(detect_os)
    local config_path=""
    
    # Determine config path
    case $os in
        "macos")
            if [[ -d "/opt/homebrew" ]]; then
                config_path="/opt/homebrew/etc/haproxy.cfg"
            elif [[ -d "/usr/local/Homebrew" ]] || [[ -d "/usr/local/etc" ]]; then
                config_path="/usr/local/etc/haproxy/haproxy.cfg"
            fi
            ;;
        "linux")
            config_path="/etc/haproxy/haproxy.cfg"
            ;;
    esac
    
    # Stop HAProxy processes
    sudo pkill -f haproxy || true
    
    # Remove our configuration
    if [[ -n "$config_path" ]]; then
        remove_haproxy_config "$config_path"
    fi
    
    echo "HAProxy cleanup complete"
}

start_haproxy() {
    local os=$1
    local config_path=$2  # Get path from create_haproxy_config
    
    echo "Starting HAProxy with config: $config_path"
    
    # Kill any existing HAProxy processes to avoid conflicts
    echo "Cleaning up any existing HAProxy processes..."
    sudo pkill -f haproxy || true
    sleep 1
    
    case $os in
        "macos")
            # For macOS, brew services don't work well with sudo for ports 80/443
            # We need to start HAProxy manually with sudo privileges
            echo "Starting HAProxy with sudo (required for ports 80/443)..."
            echo "Note: brew services won't work for privileged ports"
            
            # Start manually with sudo
            if sudo /opt/homebrew/bin/haproxy -f "$config_path" -D; then
                echo "HAProxy started manually with sudo"
            else
                echo "Failed to start HAProxy manually"
                echo "Try: sudo /opt/homebrew/bin/haproxy -f $config_path -D"
                return 1
            fi
            ;;
        "linux")
            sudo systemctl enable haproxy
            sudo systemctl restart haproxy
            ;;
    esac
    
    # Verify HAProxy is running
    sleep 2
    if pgrep -f haproxy &> /dev/null; then
        echo "HAProxy started successfully"
        
        # Verify it's listening on the right ports
        if lsof -i :80 | grep -q haproxy && lsof -i :443 | grep -q haproxy; then
            echo "HAProxy is listening on ports 80 and 443"
        else
            echo "HAProxy started but may not be listening on ports 80/443"
        fi
    else
        echo "HAProxy failed to start"
        echo "Try manually: sudo haproxy -f $config_path -D"
        return 1
    fi
}

setup_hosts_file() {
    echo "Setting up /etc/hosts entries..."
    
    local hosts_file="/etc/hosts"
    
    # Get all domains dynamically
    local domains=()
    while IFS= read -r domain; do
        domains+=("$domain")
    done < <(get_all_domains)
    
    if [[ ${#domains[@]} -eq 0 ]]; then
        echo "No *_DOMAIN variables found in configuration"
        return 1
    fi
    
    echo "Found ${#domains[@]} domain(s): ${domains[*]}"
    
    # Check if our block already exists
    local project_upper=$(echo "${PROJECT_TITLE}" | tr '[:lower:]' '[:upper:]')
    local hosts_start_marker="# === ${project_upper} DEV HOSTS START ==="
    local hosts_end_marker="# === ${project_upper} DEV HOSTS END ==="
    
    if grep -q "$hosts_start_marker" "$hosts_file" 2>/dev/null; then
        echo "${PROJECT_TITLE} hosts entries already configured"
        return 0
    fi
    
    echo "Adding hosts entries to $hosts_file..."
    
    # Create the hosts block
    local hosts_block=""
    hosts_block+="$hosts_start_marker\n"
    hosts_block+="# Local development domains for ${PROJECT_TITLE} project\n"
    for domain in "${domains[@]}"; do
        hosts_block+="127.0.0.1 $domain\n"
    done
    hosts_block+="$hosts_end_marker\n"
    
    # Add to hosts file with sudo
    if echo -e "$hosts_block" | sudo tee -a "$hosts_file" > /dev/null; then
        echo "Hosts entries added successfully"
        echo "Added domains: ${domains[*]}"
    else
        echo "Failed to add hosts entries"
        return 1
    fi
}

remove_hosts_entries() {
    echo "Removing getposture hosts entries..."
    
    local hosts_file="/etc/hosts"
    
    # Check if our block exists
    if ! grep -q "# === GETPOSTURE DEV HOSTS START ===" "$hosts_file" 2>/dev/null; then
        echo "No getposture hosts entries found"
        return 0
    fi
    
    # Remove the block using awk
    local temp_file=$(mktemp)
    
    awk '
        /^# === GETPOSTURE DEV HOSTS START ===/ { skip=1; next }
        /^# === GETPOSTURE DEV HOSTS END ===/ { skip=0; next }
        !skip { print }
    ' "$hosts_file" > "$temp_file"
    
    # Replace the hosts file with sudo
    if sudo cp "$temp_file" "$hosts_file"; then
        echo "Hosts entries removed successfully"
    else
        echo "Failed to remove hosts entries"
        rm "$temp_file"
        return 1
    fi
    
    rm "$temp_file"
}

# Function to verify certificate setup after containers are running
verify_certificate_setup() {
    echo "Verifying SSL certificate setup..."
    
    # Wait for Traefik to be ready
    echo "Waiting for Traefik to start..."
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if curl -s -f http://localhost:${TRAEFIK_DASHBOARD_PORT}/api/rawdata > /dev/null 2>&1; then
            echo "Traefik is ready"
            break
        fi
        echo "   Attempt $attempt/$max_attempts: Waiting for Traefik..."
        sleep 2
        ((attempt++))
    done
    
    if [ $attempt -gt $max_attempts ]; then
        echo "Traefik took too long to start, skipping certificate verification"
        return 1
    fi
    
    # Test certificate validation
    echo "Testing SSL certificate..."
    local test_url="https://${FRONTEND_DOMAIN}"
    
    # Test with curl (allows self-signed for testing)
    if curl -Iks --max-time 10 "$test_url" > /dev/null 2>&1; then
        echo "SSL certificate is working correctly"
        
        # Check if it's using our mkcert certificate (not Traefik default)
        local cert_subject=$(echo | openssl s_client -connect "${FRONTEND_DOMAIN}:443" -servername "${FRONTEND_DOMAIN}" 2>/dev/null | openssl x509 -noout -subject 2>/dev/null | grep "mkcert development certificate")
        
        if [[ -n "$cert_subject" ]]; then
            echo "Using mkcert certificate (not Traefik default)"
        else
            echo "Warning: Traefik may be using default certificate instead of mkcert"
            echo "   This might cause browser certificate warnings"
        fi
        
        return 0
    else
        echo "SSL certificate verification failed"
        echo "   URL tested: $test_url"
        echo "   This might cause browser certificate warnings"
        return 1
    fi
}

# Function to stop Valet services
stop_valet_services() {
    echo "Stopping Valet services..."
    
    # Stop nginx
    if sudo brew services stop nginx 2>/dev/null; then
        echo "  nginx stopped"
    else
        echo "  Failed to stop nginx (might not be running)"
    fi
    
    # Stop dnsmasq  
    if sudo brew services stop dnsmasq 2>/dev/null; then
        echo "  dnsmasq stopped"
    else
        echo "  Failed to stop dnsmasq (might not be running)"
    fi
    
    # Wait a moment for services to fully stop
    sleep 2
    
    # Verify ports are free
    if ! lsof -i :80 2>/dev/null | grep -q LISTEN && ! lsof -i :443 2>/dev/null | grep -q LISTEN; then
        echo "  Ports 80/443 are now available"
        return 0
    else
        echo "  Warning: Some processes may still be using ports 80/443"
        return 1
    fi
}

# Main detection logic
main() {
    # Handle command line arguments
    if [[ "$1" == "cleanup" ]]; then
        cleanup_haproxy
        remove_hosts_entries
        return 0
    elif [[ "$1" == "--help" || "$1" == "-h" ]]; then
        echo "Proxy Detection and Setup Script"
        echo ""
        echo "Usage: ./proxy-detection.sh [OPTIONS]"
        echo ""
        echo "Options:"
        echo "  (no args)        Auto-detect and configure local development proxy"
        echo "  --force-haproxy  Force HAProxy setup, bypass all detection"
        echo "  cleanup          Remove all proxy configurations and restore defaults"
        echo "  --help, -h       Show this help message"
        echo ""
        echo "Behavior:"
        echo "• Detects Laravel Valet and prompts to stop it (default: Yes)"
        echo "• Falls back to HAProxy for reliable .local domain support"
        echo "• Automatically configures SSL certificates and DNS resolution"
        echo ""
        exit 0
    elif [[ "$1" == "--force-haproxy" ]]; then
        echo "Forcing HAProxy setup (bypassing Valet detection)..."
        echo ""
        echo "Note: If you have Valet running, you should stop it first:"
        echo "  valet stop && valet stop dnsmasq"
        echo ""
        # Skip to port availability check
        if check_port_availability; then
            echo ""
            echo "Installing HAProxy as local development proxy..."
            if setup_haproxy; then
                echo ""
                echo "Setup complete! Your local development environment is ready."
                echo ""
                echo "Next steps:"
                echo "   1. Run: docker compose up -d"
                echo "   2. Access your sites:"
                
                # Display all configured domains dynamically
                while IFS= read -r domain; do
                    echo "      • https://$domain"
                done < <(get_all_domains | sort)
                
                echo "   3. HTTP requests will automatically redirect to HTTPS"
                echo ""
                echo "Manual restart command if needed:"
                echo "   sudo /opt/homebrew/bin/haproxy -f /opt/homebrew/etc/haproxy.cfg -D"
                echo ""
                echo "To remove this setup later:"
                echo "   ./proxy-detection.sh cleanup"
            else
                echo "HAProxy setup failed"
                return 1
            fi
            return 0
        else
            echo ""
            echo "Cannot proceed with automatic setup due to port conflicts."
            echo "Please resolve the conflicts above and try again."
            return 1
        fi
    fi
    
    echo "Running local development environment detection..."
    echo ""
    
    # Check known dev tools first
    valet_result=0
    if check_valet; then
        return 0
    else
        valet_result=$?
    fi
    
    # If Valet was stopped (return code 1), skip other checks and go to HAProxy
    if [[ $valet_result -eq 1 ]]; then
        echo ""
        echo "Proceeding with HAProxy setup..."
        # Skip to port availability check
        if check_port_availability; then
            echo ""
            echo "Installing HAProxy as local development proxy..."
            if setup_haproxy; then
                echo ""
                echo "Setup complete! Your local development environment is ready."
                echo ""
                echo "Next steps:"
                echo "   1. Run: docker compose up -d"
                echo "   2. Access your sites:"
                
                # Display all configured domains dynamically
                while IFS= read -r domain; do
                    echo "      • https://$domain"
                done < <(get_all_domains | sort)
                
                echo "   3. HTTP requests will automatically redirect to HTTPS"
                echo ""
                echo "Manual restart command if needed:"
                echo "   sudo /opt/homebrew/bin/haproxy -f /opt/homebrew/etc/haproxy.cfg -D"
                echo ""
                echo "To remove this setup later:"
                echo "   ./proxy-detection.sh cleanup"
                return 0
            else
                echo "HAProxy setup failed"
                return 1
            fi
        else
            echo ""
            echo "Cannot proceed with automatic setup due to port conflicts."
            echo "Please resolve the conflicts above and try again."
            return 1
        fi
    fi
    
    if check_local_flywheel; then
        echo "Please resolve the Local by Flywheel conflict before continuing."
        return 1
    fi
    
    if check_mamp_xampp; then
        echo "Please resolve the MAMP/XAMPP conflict before continuing."
        return 1
    fi
    
    if check_existing_nginx; then
        return 0
    fi
    
    if check_existing_apache; then
        echo "Please resolve the Apache conflict before continuing."
        return 1
    fi
    
    echo ""
    echo "No known dev tools detected, checking port availability..."
    
    # Check if ports are available
    if check_port_availability; then
        echo ""
        echo "Installing HAProxy as local development proxy..."
        if setup_haproxy; then
            echo ""
            echo "Setup complete! Your local development environment is ready."
            echo ""
            echo "Next steps:"
            echo "   1. Run: docker compose up -d"
            echo "   2. Access your sites:"
            
            # Display all configured domains dynamically
            while IFS= read -r domain; do
                echo "      • https://$domain"
            done < <(get_all_domains | sort)
            
            echo "   3. HTTP requests will automatically redirect to HTTPS"
            echo ""
            echo "Manual restart command if needed:"
            echo "   sudo /opt/homebrew/bin/haproxy -f /opt/homebrew/etc/haproxy.cfg -D"
            echo ""
            echo "To remove this setup later:"
            echo "   ./proxy-detection.sh cleanup"
        else
            echo "HAProxy setup failed"
            return 1
        fi
        return 0
    else
        echo ""
        echo "Cannot proceed with automatic setup due to port conflicts."
        echo "Please resolve the conflicts above and try again."
        return 1
    fi
}

# Run the detection
main "$@"