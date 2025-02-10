#!/usr/bin/env groovy

def call(String inventoryFile, String playbookFile, String repoUrl, String webhookUrl, String githubToken) {
    sh """
        ansible-playbook -i ${inventoryFile} ${playbookFile} \
            -e GIT_REPO_URL=${repoUrl} \
            -e WEBHOOK_URL=${webhookUrl} \
            -e GITHUB_TOKEN=${githubToken}
    """
}