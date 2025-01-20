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
    
    # Use sed with multiple patterns to handle all scenarios
    sed -E '
    # Scenario 1: TypeScript with type declaration and multiple lines
    /^const nextConfig: NextConfig = \{/ {
        N
        s/(const nextConfig: NextConfig = \{)\n(\s*)/\1\n    output: "standalone",\n\2/
    }
    
    # Scenario 2: TypeScript with empty config
    /^const nextConfig: NextConfig = \{\};/ {
        s/\{\}/{\n    output: "standalone",\n}/
    }
    
    # Scenario 3: JavaScript module.exports with multiple lines
    /^module\.exports = \{/ {
        N
        s/(module\.exports = \{)\n(\s*)/\1\n    output: "standalone",\n\2/
    }
    
    # Scenario 4: JavaScript module.exports empty config
    /^module\.exports = \{\};/ {
        s/\{\}/{\n    output: "standalone",\n}/
    }
    
    # Scenario 5: ES Modules export with multiple lines
    /^export default \{/ {
        N
        s/(export default \{)\n(\s*)/\1\n    output: "standalone",\n\2/
    }
    
    # Scenario 6: ES Modules empty export
    /^export default \{\};/ {
        s/\{\}/{\n    output: "standalone",\n}/
    }
    
    # Scenario 7: Function-wrapped config
    /return \{/ {
        N
        s/(return \{)\n(\s*)/\1\n    output: "standalone",\n\2/
    }
    
    # Scenario 8: One-line configs
    /^(const nextConfig: NextConfig = |module\.exports = |export default )\{ ?([^}]*)\};?/ {
        s/\{([^}]*)\}/{\n    output: "standalone",\1\n}/
    }
    
    # Scenario 9: Configs with withPlugins
    /^(const nextConfig = .*withPlugins\(\[[^\]]*\],) \{/ {
        N
        s/(\{)\n(\s*)/\1\n    output: "standalone",\n\2/
    }
    ' "$config_file" > "$temp_file"

    # Check if the file was modified
    if ! cmp -s "$config_file" "$temp_file"; then
        mv "$temp_file" "$config_file"
        echo "Updated $config_file with standalone configuration"
    else
        rm "$temp_file"
        echo "No changes were made. Please check your config file format."
        
        # Show the current config file content for debugging
        echo "Current config file content:"
        cat "$config_file"
    fi
}

# Run the update function
update_next_config

echo "Setup complete! Your Next.js project is now configured for standalone output"
cat next.config.ts