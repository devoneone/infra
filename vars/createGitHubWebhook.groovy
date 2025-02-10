#!/usr/bin/env groovy

def call(String repoUrl, String webhookUrl, String githubToken) {
    // Validate inputs
    if (!repoUrl || !webhookUrl || !githubToken) {
        error "Missing required parameters for GitHub webhook creation"
    }

    // Extract owner and repo from the repository URL
    def (owner, repo) = extractRepoDetails(repoUrl)
    def apiUrl = "https://api.github.com/repos/${owner}/${repo}/hooks"

    // Generate a secure random secret
    def webhookSecret = generateWebhookSecret()

    // Webhook payload
    def webhookPayload = [
        name: "web",
        active: true,
        events: ["push"],
        config: [
            url: webhookUrl,
            content_type: "json",
            insecure_ssl: "0",
            secret: webhookSecret
        ]
    ]

    // Convert payload to JSON
    def payloadJson = groovy.json.JsonOutput.toJson(webhookPayload)

    // Execute webhook creation with verbose error checking
    def response = sh(
        script: """
            response=$(curl -s -w "\\nHTTP_STATUS:%{http_code}" \
                -X POST \
                -H "Authorization: token ${githubToken}" \
                -H "Accept: application/vnd.github.v3+json" \
                -H "Content-Type: application/json" \
                -d '${payloadJson}' \
                "${apiUrl}")
            
            body=$(echo "$response" | sed -e '$d')
            http_status=$(echo "$response" | tail -n1 | sed -e 's/HTTP_STATUS://')
            
            echo "Response Body: $body"
            echo "HTTP Status: $http_status"
            
            if [ "$http_status" -ne 201 ]; then
                exit 1
            fi
        """,
        returnStdout: true
    ).trim()

    echo "Webhook creation response: ${response}"
}

// Helper method to extract owner and repo from repository URL
def extractRepoDetails(String repoUrl) {
    def matcher = repoUrl =~ /.*[\/:]([^\/]+)\/([^\/]+)\.git/
    if (matcher.find()) {
        return [matcher.group(1), matcher.group(2)]
    }
    error "Invalid repository URL format: ${repoUrl}"
}

// Helper method to generate a secure webhook secret
def generateWebhookSecret() {
    return sh(
        script: "openssl rand -hex 20",
        returnStdout: true
    ).trim()
}