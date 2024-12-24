update_next_config() {
    local config_file=""
    
    # Check which config file exists
    if [ -f "next.config.js" ]; then
        config_file="next.config.js"
    elif [ -f "next.config.ts" ]; then
        config_file="next.config.ts"
    elif [ -f "next.config.mjs" ]; then
        config_file="next.config.mjs"
    else
        echo "No next.config file found"
        return 1
    fi
    
    echo "Found config file: $config_file"
    
    # Check if output: "standalone" already exists
    if grep -q "output.*:.*\"standalone\"" "$config_file"; then
        echo "Standalone configuration already exists in $config_file"
        return 0
    fi
    
    # Create temporary file
    local temp_file=$(mktemp)
    
    # Add output: "standalone" to the nextConfig object
    awk '
    /const nextConfig/ {
        print $0
        print "    output: \"standalone\","
        next
    }
    { print $0 }
    ' "$config_file" > "$temp_file"
    
    # Replace original file with modified content
    mv "$temp_file" "$config_file"
    
    echo "Updated $config_file with standalone configuration"
}

# Run the update function
update_next_config

echo "Setup complete! Your Next.js project is now configured for standalone output"