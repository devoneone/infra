#!/usr/bin/env groovy

def call(String repoUrl, String webhookUrl, String githubToken) {
    // Comprehensive Logging and Debugging
    println "DEBUG: Starting GitHub Webhook Creation Process"
    println "DEBUG: Input Parameters:"
    println "  - Repository URL: ${repoUrl}"
    println "  - Webhook URL: ${webhookUrl}"
    println "  - GitHub Token Length: ${githubToken.length()} characters"

    // Validate inputs
    if (!repoUrl || !webhookUrl || !githubToken) {
        error "CRITICAL ERROR: Missing required parameters for GitHub webhook creation"
    }

    // Extract owner and repo from the repository URL
    def (owner, repo) = extractRepoDetails(repoUrl)
    println "DEBUG: Extracted Repository Details:"
    println "  - Owner: ${owner}"
    println "  - Repository: ${repo}"

    def apiUrl = "https://api.github.com/repos/${owner}/${repo}/hooks"
    println "DEBUG: GitHub API Endpoint: ${apiUrl}"

    // Generate a secure random secret
    def webhookSecret = generateWebhookSecret()
    println "DEBUG: Generated Webhook Secret: ${webhookSecret}"

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
    println "DEBUG: Webhook Payload JSON:"
    println payloadJson

    // Verbose Curl Command with Detailed Logging
    def curlCommand = """
        curl -v -s -X POST \\
            -H "Authorization: Bearer ${githubToken}" \\
            -H "Content-Type: application/json" \\
            -H "Accept: application/vnd.github.v3+json" \\
            -d '${payloadJson}' \\
            "${apiUrl}"
    """

    println "DEBUG: Curl Command:"
    println curlCommand

    // Execute webhook creation with full output capture
    def response = sh(
        script: curlCommand,
        returnStdout: true
    ).trim()

    println "DEBUG: Raw Response:"
    println response

    // Additional Token Validation
    validateToken(githubToken)

    // Parse and validate response
    def jsonResponse = parseJsonSafely(response)
    
    if (jsonResponse.containsKey('id')) {
        println "SUCCESS: Webhook created successfully for ${repoUrl}"
        println "Webhook ID: ${jsonResponse.id}"
    } else {
        def errorMessage = jsonResponse.message ?: "Unknown error occurred"
        def fullErrorDetails = """
        WEBHOOK CREATION FAILED
        - Error Message: ${errorMessage}
        - Repository: ${repoUrl}
        - Webhook URL: ${webhookUrl}
        - Full Response: ${response}
        """
        
        error fullErrorDetails
    }
}

// Additional Token Validation Method
def validateToken(String githubToken) {
    println "DEBUG: Validating GitHub Token..."
    
    def tokenValidationResponse = sh(
        script: """
            curl -s -H "Authorization: Bearer ${githubToken}" \\
                 -H "Accept: application/vnd.github.v3+json" \\
                 https://api.github.com/user
        """,
        returnStdout: true
    ).trim()

    println "DEBUG: Token Validation Response:"
    println tokenValidationResponse

    def validationResult = parseJsonSafely(tokenValidationResponse)
    
    if (validationResult.containsKey('login')) {
        println "SUCCESS: Token is valid for GitHub user: ${validationResult.login}"
    } else {
        error "CRITICAL: Invalid GitHub Token - Unable to authenticate user"
    }
}

// Helper method to extract owner and repo from repository URL
def extractRepoDetails(String repoUrl) {
    println "DEBUG: Extracting Repository Details from URL: ${repoUrl}"
    
    def matcher = repoUrl =~ /.*[\/:]([^\/]+)\/([^\/]+)\.git/
    if (matcher.find()) {
        def owner = matcher.group(1)
        def repo = matcher.group(2)
        println "  - Extracted Owner: ${owner}"
        println "  - Extracted Repo: ${repo}"
        return [owner, repo]
    }
    error "CRITICAL: Invalid repository URL format: ${repoUrl}"
}

// Helper method to generate a secure webhook secret
def generateWebhookSecret() {
    def secret = sh(
        script: "openssl rand -hex 20",
        returnStdout: true
    ).trim()
    
    println "DEBUG: Generated Webhook Secret (length: ${secret.length()})"
    return secret
}

// Helper method to safely parse JSON
def parseJsonSafely(String jsonString) {
    try {
        def parsedJson = new groovy.json.JsonSlurperClassic().parseText(jsonString)
        println "DEBUG: JSON Parsing Successful"
        return parsedJson
    } catch (Exception e) {
        error "CRITICAL: Failed to parse JSON response: ${jsonString}\nError: ${e.message}"
    }
}