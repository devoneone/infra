#!/usr/bin/env groovy

def call(Map config = [:]) {
    // Extract owner and repo using string manipulation
    String repoUrl = config.repoUrl ?: env.GIT_REPO_URL
    String githubToken = config.githubToken ?: env.GITHUB_TOKEN
    String webhookUrl = config.webhookUrl ?: env.WEBHOOK_URL
    
    List parts = repoUrl.replaceAll('\\.git$', '').split('/|:')
    String owner = parts[-2]
    String repo = parts[-1]
    
    // Validate GitHub Token
    validateGitHubToken(githubToken)
    
    // Generate webhook secret
    String webhookSecret = sh(
        script: 'openssl rand -hex 20',
        returnStdout: true
    ).trim()
    
    // Create webhook
    createWebhook(owner, repo, webhookSecret, githubToken, webhookUrl)
}

private void validateGitHubToken(String token) {
    def response = sh(
        script: """
            curl -s -w "%{http_code}" \\
                -H "Authorization: Bearer ${token}" \\
                -H "Accept: application/vnd.github.v3+json" \\
                https://api.github.com/user
        """,
        returnStdout: true
    ).trim()
    def statusCode = response[-3..-1]
    
    if (statusCode != '200') {
        error """
        GitHub Token Validation Failed
        Status Code: ${statusCode}
        
        Possible reasons:
        - Token expired
        - Insufficient permissions
        - Network issues
        """
    }
}

private void createWebhook(String owner, String repo, String webhookSecret, String token, String webhookUrl) {
    def webhookPayload = new groovy.json.JsonOutput().toJson([
        name: "web",
        active: true,
        events: ["push"],
        config: [
            url: webhookUrl,
            content_type: "json",
            insecure_ssl: "0",
            secret: webhookSecret
        ]
    ])
    
    def response = sh(
        script: """
            curl -s -w "%{http_code}" \\
                -X POST \\
                -H "Authorization: Bearer ${token}" \\
                -H "Content-Type: application/json" \\
                -d '${webhookPayload}' \\
                https://api.github.com/repos/${owner}/${repo}/hooks
        """,
        returnStdout: true
    ).trim()
    def statusCode = response[-3..-1]
    
    if (statusCode != '201') {
        error """
        Webhook Creation Failed
        Status Code: ${statusCode}
        
        Possible reasons:
        - Insufficient repository permissions
        - Webhook already exists
        - GitHub API restrictions
        """
    }
}