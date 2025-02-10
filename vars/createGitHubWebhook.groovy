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

    // Execute webhook creation
    def response = sh(
        script: """
            curl -s -X POST \
                -H "Authorization: Bearer ${githubToken}" \
                -H "Content-Type: application/json" \
                -d '${payloadJson}' \
                "${apiUrl}"
        """,
        returnStdout: true
    ).trim()

    // Parse and validate response
    def jsonResponse = parseJsonSafely(response)
    
    if (jsonResponse.containsKey('id')) {
        echo "Webhook created successfully for ${repoUrl}"
    } else {
        def errorMessage = jsonResponse.message ?: "Unknown error occurred"
        error "Failed to create webhook: ${errorMessage} - Full response: ${response}"
    }
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

// Helper method to safely parse JSON
def parseJsonSafely(String jsonString) {
    try {
        return new groovy.json.JsonSlurperClassic().parseText(jsonString)
    } catch (Exception e) {
        error "Failed to parse JSON response: ${jsonString}"
    }
}