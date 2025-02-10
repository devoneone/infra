#!/usr/bin/env groovy

import groovy.json.JsonOutput
import groovy.json.JsonSlurperClassic

def call(String repoUrl, String webhookUrl, String githubToken) {
    // Input validation
    if (!githubToken) {
        echo "GitHub token is null, skipping webhook creation."
        return
    }

    // Constants
    def WEBHOOK_SECRET = '115c6b3844198294586262c6404939d29e'
    
    // Parse repository URL
    def repoParts = repoUrl.tokenize('/')
    def owner = repoParts[-2]
    def repo = repoParts[-1].replace('.git', '')
    def apiUrl = "https://api.github.com/repos/${owner}/${repo}/hooks"

    // Log operation details
    echo "Creating webhook for ${repo} repository..."
    echo "API URL: ${apiUrl}"
    echo "Webhook URL: ${webhookUrl}"
    echo "Owner: ${owner}"
    echo "Repo: ${repo}"

    // Check existing webhooks
    def existingWebhooksResponse = sh(
        script: """
            curl -s \
                -H 'Accept: application/vnd.github.v3+json' \
                -H 'Authorization: Bearer ${githubToken}' \
                "${apiUrl}"
        """,
        returnStdout: true
    ).trim()

    echo "Existing webhooks response: ${existingWebhooksResponse}"

    // Parse response
    def existingWebhooks
    try {
        existingWebhooks = new JsonSlurperClassic().parseText(existingWebhooksResponse)
        
        // Check for API error response
        if (existingWebhooks.message) {
            error "GitHub API error: ${existingWebhooks.message}"
            return
        }
    } catch (Exception e) {
        error "Failed to parse existing webhooks response: ${e.message}"
    }

    // Validate response format
    if (!(existingWebhooks instanceof List)) {
        error "Unexpected response format for existing webhooks: ${existingWebhooksResponse}"
    }

    // Check if webhook already exists
    def webhookExists = existingWebhooks.find { it?.config?.url == webhookUrl }
    if (webhookExists) {
        echo "Webhook already exists: ${webhookExists.url}"
        return
    }

    // Prepare webhook payload
    def webhookPayload = JsonOutput.toJson([
        "name": "web",
        "active": true,
        "events": ["push"],
        "config": [
            "url": webhookUrl,
            "content_type": "json",
            "insecure_ssl": "0",
            "secret": WEBHOOK_SECRET
        ]
    ])

    // Create webhook
    def response = sh(
        script: """
            curl -s -X POST \
                -H 'Accept: application/vnd.github.v3+json' \
                -H 'Authorization: Bearer ${githubToken}' \
                -H 'Content-Type: application/json' \
                -d '${webhookPayload}' \
                "${apiUrl}"
        """,
        returnStdout: true
    ).trim()

    echo "Create webhook response: ${response}"

    // Parse and validate response
    def jsonResponse
    try {
        jsonResponse = new JsonSlurperClassic().parseText(response)
        
        // Check for API error response
        if (jsonResponse.message) {
            error "GitHub API error: ${jsonResponse.message}"
            return
        }
    } catch (Exception e) {
        error "Failed to parse webhook creation response: ${e.message}"
    }

    if (jsonResponse?.id) {
        echo "Webhook created successfully: ${jsonResponse.url}"
    } else {
        error "Failed to create webhook: ${jsonResponse?.message ?: 'Unknown error'}"
    }
}