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
        // Validate token first
        def tokenValidation = validateToken(githubToken)
        
        if (!tokenValidation.valid) {
            error "❌ TOKEN VALIDATION FAILED: ${tokenValidation.message}"
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

        // Execute webhook creation
        def response = sh(
            script: """
                curl -v -f -X POST \
                    -H "Authorization: Bearer ${githubToken}" \
                    -H "Content-Type: application/json" \
                    -H "Accept: application/vnd.github.v3+json" \
                    -d '${payloadJson}' \
                    "${apiUrl}"
            """,
            returnStdout: true
        ).trim()

        println "✅ Webhook created successfully"
        return true

    } catch (Exception e) {
        println "❌ WEBHOOK CREATION FAILED"
        println "Error Details: ${e.message}"
        error "Webhook creation process encountered a critical error: ${e.message}"
    }
}

// Token validation method
def validateToken(String githubToken) {
    try {
        def response = sh(
            script: """
                curl -s -f -H "Authorization: Bearer ${githubToken}" \
                     -H "Accept: application/vnd.github.v3+json" \
                     https://api.github.com/user
            """,
            returnStdout: true
        ).trim()

        def jsonResponse = new groovy.json.JsonSlurperClassic().parseText(response)
        
        if (jsonResponse.login) {
            println "✅ Token is valid for GitHub user: ${jsonResponse.login}"
            return [valid: true, message: "Token is valid", username: jsonResponse.login]
        } else {
            println "❌ Token validation failed"
            return [valid: false, message: "Unable to validate token"]
        }
    } catch (Exception e) {
        println "❌ Token validation error: ${e.message}"
        return [valid: false, message: "Token validation error"]
    }
}

// Extract repository details from URL
def extractRepoDetails(String repoUrl) {
    def matcher = repoUrl =~ /.*[\/:]([^\/]+)\/([^\/]+)\.git/
    if (matcher.find()) {
        def owner = matcher.group(1)
        def repo = matcher.group(2)
        return [owner, repo]
    }
    error "Invalid repository URL format: ${repoUrl}"
}

// Generate secure webhook secret
def generateWebhookSecret() {
    return sh(
        script: "openssl rand -hex 20",
        returnStdout: true
    ).trim()
}