#!/usr/bin/env groovy

def call(String repoUrl, String webhookUrl, String githubToken) {
    // Create a temporary directory for the script
    def scriptDir = "${env.WORKSPACE}/temp_scripts"
    def scriptPath = "${scriptDir}/webhook_creator.sh"
    
    try {
        // Create directory and script
        sh """
            mkdir -p ${scriptDir}
            cat << 'EOF' > ${scriptPath}
#!/bin/bash

# Function to display usage information
usage() {
    echo "Usage: \$0 -r REPO_URL -w WEBHOOK_URL -t GITHUB_TOKEN"
    exit 1
}

# Parse command line arguments
while getopts ":r:w:t:" opt; do
    case \$opt in
        r) REPO_URL="\$OPTARG";;
        w) WEBHOOK_URL="\$OPTARG";;
        t) GITHUB_TOKEN="\$OPTARG";;
        \\?) echo "Invalid option -\$OPTARG" >&2; usage;;
        :) echo "Option -\$OPTARG requires an argument." >&2; usage;;
    esac
done

# Validate inputs
if [ -z "\$REPO_URL" ] || [ -z "\$WEBHOOK_URL" ] || [ -z "\$GITHUB_TOKEN" ]; then
    echo "Error: Missing required arguments"
    usage
fi

# Extract owner and repo from the repository URL
OWNER=\$(echo "\$REPO_URL" | sed -E 's/.*[:/]([^/]+)\/([^/]+)\.git/\\1/')
REPO=\$(echo "\$REPO_URL" | sed -E 's/.*[:/]([^/]+)\/([^/]+)\.git/\\2/')
API_URL="https://api.github.com/repos/\${OWNER}/\${REPO}/hooks"
WEBHOOK_SECRET="115c6b3844198294586262c6404939d29e"

echo "Creating webhook for \${REPO} repository..."
echo "API URL: \${API_URL}"
echo "Webhook URL: \${WEBHOOK_URL}"
echo "Owner: \${OWNER}"
echo "Repo: \${REPO}"

# Check if webhook already exists
EXISTING_WEBHOOKS=\$(curl -s -H "Authorization: token \${GITHUB_TOKEN}" "\${API_URL}")

if echo "\$EXISTING_WEBHOOKS" | grep -q '"message":'; then
    ERROR_MSG=\$(echo "\$EXISTING_WEBHOOKS" | grep -o '"message": *"[^"]*"' | cut -d'"' -f4)
    echo "Error accessing webhooks: \$ERROR_MSG"
    exit 1
fi

if echo "\$EXISTING_WEBHOOKS" | grep -q "\"\$WEBHOOK_URL\""; then
    echo "Webhook already exists"
    exit 0
fi

# Create webhook payload
WEBHOOK_PAYLOAD="{
    \\"name\\": \\"web\\",
    \\"active\\": true,
    \\"events\\": [\\"push\\"],
    \\"config\\": {
        \\"url\\": \\"\${WEBHOOK_URL}\\",
        \\"content_type\\": \\"json\\",
        \\"insecure_ssl\\": \\"0\\",
        \\"secret\\": \\"\${WEBHOOK_SECRET}\\"
    }
}"

# Create webhook
RESPONSE=\$(curl -s -X POST \\
    -H "Authorization: token \${GITHUB_TOKEN}" \\
    -H "Content-Type: application/json" \\
    -d "\$WEBHOOK_PAYLOAD" \\
    "\${API_URL}")

if echo "\$RESPONSE" | grep -q '"id":'; then
    echo "Webhook created successfully"
    exit 0
else
    ERROR_MSG=\$(echo "\$RESPONSE" | grep -o '"message": *"[^"]*"' | cut -d'"' -f4)
    echo "Failed to create webhook: \$ERROR_MSG"
    exit 1
fi
EOF

            chmod +x ${scriptPath}
        """
        
        // Execute the script with parameters
        sh """
            ${scriptPath} -r "${repoUrl}" -w "${webhookUrl}" -t "${githubToken}"
        """
        
    } catch (Exception e) {
        error "Failed to create webhook: ${e.message}"
    } finally {
        // Cleanup
        sh "rm -rf ${scriptDir}"
    }
}