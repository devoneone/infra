import groovy.json.JsonOutput
import groovy.json.JsonSlurper

def call(String repoUrl, String webhookUrl, String githubToken) {
    if (!githubToken) {
        echo "GitHub token is null, skipping webhook creation."
        return
    }

    def WEBHOOK_SECRET = '11c115bda74c0bb162b49344386a82c43b'
    def repoParts = repoUrl.tokenize('/')
    def owner = repoParts[-2]
    def repo = repoParts[-1].replace('.git', '')

    def apiUrl = "https://api.github.com/repos/${owner}/${repo}/hooks"

    echo "Creating webhook for ${repo} repository..."
    echo "API URL: ${apiUrl}"
    echo "Webhook URL: ${webhookUrl}"
    echo "GitHub Token: ${githubToken}"
    echo "Webhook Secret: ${WEBHOOK_SECRET}"
    echo "Owner: ${owner}"
    echo "Repo: ${repo}"

    // Fetch existing webhooks
    def existingWebhooksResponse = sh(
        script: """
            curl -s -H "Authorization: Bearer ${githubToken}" "${apiUrl}"
        """,
        returnStdout: true
    )

    def existingWebhooks = new JsonSlurper().parseText(existingWebhooksResponse)
    def webhookExists = existingWebhooks.find { it.config.url == webhookUrl }

    if (webhookExists) {
        echo "Webhook already exists: ${webhookExists.url}"
        return
    }

    // Prepare the webhook configuration payload
    def webhookPayload = JsonOutput.toJson([
        "name"   : "web",
        "active" : true,
        "events" : ["push"],
        "config" : [
            "url"          : webhookUrl,
            "content_type" : "json",
            "insecure_ssl" : "0",
            "secret"       : WEBHOOK_SECRET
        ]
    ])

    // Make the request to GitHub's API to create the webhook
    def response = sh(
        script: """
            curl -s -X POST -H "Authorization: Bearer ${githubToken}" \
                 -H "Content-Type: application/json" \
                 -d '${webhookPayload}' \
                 "${apiUrl}"
        """,
        returnStdout: true
    )

    // Check if the webhook was created successfully
    def jsonResponse = new JsonSlurper().parseText(response)
    if (jsonResponse.id) {
        echo "Webhook created successfully: ${jsonResponse.url}"
    } else {
        error "Failed to create webhook: ${jsonResponse.message}"
    }
}