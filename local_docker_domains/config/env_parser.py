# Parse .env.local for domains

'''
# source environment variables to get specified domain + proxy configuration
if [[ -f ".env.local" ]]; then
    source .env.local
     echo "✅ Loaded .env.local configuration"
elif [[ -f ".env" ]]; then
    source .env
	echo "⚠️  Loaded .env configuration"
	echo "   💡 Tip: Create .env.local for local-only settings"
else
    echo -e "\e[31m❌ Missing configuration file (.env.local or .env).\e[0m"
    exit 1
fi

# utility function to discover all domain variables
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
'''
