import groovy.json.JsonOutput
import groovy.json.JsonSlurperClassic

def createGitHubWebhook(String repoUrl, String webhookUrl, String githubToken) {
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
    echo "Owner: ${owner}"
    echo "Repo: ${repo}"

    // Fetch existing webhooks
    def existingWebhooksResponse = sh(
        script: """
            curl -s -H "Authorization: token ${githubToken}" "${apiUrl}"
        """,
        returnStdout: true
    ).trim()

    echo "Existing webhooks response: ${existingWebhooksResponse}"

    def existingWebhooks
    try {
        existingWebhooks = new JsonSlurperClassic().parseText(existingWebhooksResponse)
    } catch (Exception e) {
        error "Failed to parse existing webhooks response: ${e.message}"
    }

    if (!(existingWebhooks instanceof List)) {
        error "Unexpected response format for existing webhooks: ${existingWebhooksResponse}"
    }

    def webhookExists = existingWebhooks.find { it?.config?.url == webhookUrl }

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
            curl -s -X POST -H "Authorization: token ${githubToken}" \
                 -H "Content-Type: application/json" \
                 -d '${webhookPayload}' \
                 "${apiUrl}"
        """,
        returnStdout: true
    ).trim()

    echo "Create webhook response: ${response}"

    def jsonResponse
    try {
        jsonResponse = new JsonSlurperClassic().parseText(response)
    } catch (Exception e) {
        error "Failed to parse webhook creation response: ${e.message}"
    }

    if (jsonResponse?.id) {
        echo "Webhook created successfully: ${jsonResponse.url}"
    } else {
        error "Failed to create webhook: ${jsonResponse?.message ?: 'Unknown error'}"
    }
}
