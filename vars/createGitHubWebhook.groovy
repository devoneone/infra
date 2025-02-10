#!/usr/bin/env groovy

def call(String repoUrl, String webhookUrl, String githubToken) {
    println "🚨 GitHub Webhook Creation Process Started"
    println "Repository URL: ${repoUrl}"
    println "Webhook URL: ${webhookUrl}"

    // Input validation
    if (!repoUrl || !webhookUrl || !githubToken) {
        error "CRITICAL: Missing required parameters for webhook creation"
    }

    try {
        // Validate token first with verbose output
        def tokenValidationScript = """
            response=$(curl -v -s -w "%{http_code}" \
                -H "Authorization: Bearer ${githubToken}" \
                -H "Accept: application/vnd.github.v3+json" \
                https://api.github.com/user)
            
            http_code=$(echo "$response" | tail -n1)
            body=$(echo "$response" | sed '$d')
            
            echo "HTTP Status Code: $http_code"
            echo "Response Body: $body"
            
            if [ "$http_code" -ne 200 ]; then
                exit 1
            fi
        """

        def tokenValidationResult = sh(
            script: tokenValidationScript,
            returnStatus: true,
            label: "Token Validation"
        )

        if (tokenValidationResult != 0) {
            error "❌ TOKEN VALIDATION FAILED: Unable to authenticate with GitHub"
        }

        // Extract repository details
        def (owner, repo) = extractRepoDetails(repoUrl)
        def apiUrl = "https://api.github.com/repos/${owner}/${repo}/hooks"

        // Generate webhook secret
        def webhookSecret = generateWebhookSecret()

        // Prepare webhook payload
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

        // Execute webhook creation with verbose output
        def webhookCreationScript = """
            response=$(curl -v -s -w "%{http_code}" \
                -H "Authorization: Bearer ${githubToken}" \
                -H "Content-Type: application/json" \
                -H "Accept: application/vnd.github.v3+json" \
                -d '${payloadJson}' \
                "${apiUrl}")
            
            http_code=$(echo "$response" | tail -n1)
            body=$(echo "$response" | sed '$d')
            
            echo "Webhook Creation HTTP Status Code: $http_code"
            echo "Webhook Creation Response Body: $body"
            
            if [ "$http_code" -ne 201 ]; then
                exit 1
            fi
        """

        def webhookCreationResult = sh(
            script: webhookCreationScript,
            returnStatus: true,
            label: "Webhook Creation"
        )

        if (webhookCreationResult != 0) {
            error "❌ WEBHOOK CREATION FAILED: Unable to create webhook"
        }

        println "✅ Webhook created successfully"
        return true

    } catch (Exception e) {
        println "❌ CRITICAL ERROR DURING WEBHOOK PROCESS"
        println "Detailed Error: ${e.message}"
        error "Webhook creation failed: ${e.message}"
    }
}

// Existing helper methods remain the same
def extractRepoDetails(String repoUrl) {
    def matcher = repoUrl =~ /.*[\/:]([^\/]+)\/([^\/]+)\.git/
    if (matcher.find()) {
        def owner = matcher.group(1)
        def repo = matcher.group(2)
        return [owner, repo]
    }
    error "Invalid repository URL format: ${repoUrl}"
}

def generateWebhookSecret() {
    return sh(
        script: "openssl rand -hex 20",
        returnStdout: true
    ).trim()
}