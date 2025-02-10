#!/bin/bash

# Check if all required arguments are provided
if [ "$#" -ne 3 ]; then
    echo "Usage: $0 REPO_URL WEBHOOK_URL GITHUB_TOKEN"
    exit 1
fi

REPO_URL="$1"
WEBHOOK_URL="$2"
GITHUB_TOKEN="$3"
WEBHOOK_SECRET="115c6b3844198294586262c6404939d29e"

# Extract owner and repo from the repository URL
OWNER=$(echo "$REPO_URL" | sed -E 's/.*[:/]([^/]+)\/([^/]+)\.git/\1/')
REPO=$(echo "$REPO_URL" | sed -E 's/.*[:/]([^/]+)\/([^/]+)\.git/\2/')
API_URL="https://api.github.com/repos/${OWNER}/${REPO}/hooks"

echo "Creating webhook for ${REPO} repository..."
echo "API URL: ${API_URL}"
echo "Webhook URL: ${WEBHOOK_URL}"
echo "Owner: ${OWNER}"
echo "Repo: ${REPO}"

# Check if webhook already exists
EXISTING_WEBHOOKS=$(curl -s -H "Authorization: token ${GITHUB_TOKEN}" "${API_URL}")

# Check if the response contains an error
if echo "$EXISTING_WEBHOOKS" | grep -q '"message"': ; then
    ERROR_MSG=$(echo "$EXISTING_WEBHOOKS" | grep -o '"message": *"[^"]*"' | cut -d'"' -f4)
    echo "Error: $ERROR_MSG"
    exit 1
fi

# Check if webhook already exists
if echo "$EXISTING_WEBHOOKS" | grep -q "\"url\": \"$WEBHOOK_URL\""; then
    echo "Webhook already exists"
    exit 0
fi

# Create webhook payload
WEBHOOK_PAYLOAD="{
    \"name\": \"web\",
    \"active\": true,
    \"events\": [\"push\"],
    \"config\": {
        \"url\": \"${WEBHOOK_URL}\",
        \"content_type\": \"json\",
        \"insecure_ssl\": \"0\",
        \"secret\": \"${WEBHOOK_SECRET}\"
    }
}"

# Create webhook
RESPONSE=$(curl -s -X POST \
    -H "Authorization: token ${GITHUB_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "$WEBHOOK_PAYLOAD" \
    "${API_URL}")

# Check if webhook creation was successful
if echo "$RESPONSE" | grep -q '"id":'; then
    echo "Webhook created successfully"
    exit 0
else
    ERROR_MSG=$(echo "$RESPONSE" | grep -o '"message": *"[^"]*"' | cut -d'"' -f4)
    echo "Failed to create webhook: $ERROR_MSG"
    exit 1
fi