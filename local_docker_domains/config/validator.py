
'''
# validate a few required environment variables
validate_project_config() {
    [[ -n "$PROJECT_TITLE" ]] || { echo "PROJECT_TITLE is required"; return 1; }
    [[ -n "$PROJECT_DOMAIN" ]] || { echo "PROJECT_DOMAIN is required"; return 1; }
}

get_traefik_config() {
    echo "Dashboard port: ${TRAEFIK_DASHBOARD_PORT:-8080}"
    echo "HTTP port: ${TRAEFIK_HTTP_PORT:-80}"
    echo "HTTPS port: ${TRAEFIK_HTTPS_PORT:-443}"
}
'''