#!/bin/bash

# Configuration
NEXUS_URL="https://nex.psa-khmer.world/repository/helm-store/"
NEXUS_USER="admin"
NEXUS_PASS="admin"
GIT_REPO_URL="https://github.com/ruos-sovanra/argocd.git"
GIT_USER="ruos-sovanra"
GIT_TOKEN="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"

# Function to download the Helm chart from Nexus
download_helm_chart() {
    local chart_name=$1
    local chart_version=$2
    local chart_file="${chart_name}-${chart_version}.tgz"

    echo "Downloading Helm chart ${chart_file} from Nexus..."
    curl -u "${NEXUS_USER}:${NEXUS_PASS}" -O "${NEXUS_URL}/${chart_file}"

    if [ ! -f "${chart_file}" ]; then
        echo "Error: Failed to download ${chart_file} from Nexus."
        exit 1
    fi
}

# Function to unzip the Helm chart
unzip_helm_chart() {
    local chart_file=$1

    echo "Unzipping Helm chart ${chart_file}..."
    tar -xzvf "${chart_file}"

    if [ $? -ne 0 ]; then
        echo "Error: Failed to unzip ${chart_file}."
        exit 1
    fi
}

# Function to initialize Git repository and push to remote
sync_to_git() {
    local chart_name=$1

    echo "Initializing Git repository for ${chart_name}..."
    cd "${chart_name}"
    git init

    echo "Adding files to Git..."
    git add .

    echo "Committing changes..."
    git commit -m "Update Helm chart: ${chart_name}"

    echo "Setting up Git remote..."
    git remote add origin "${GIT_REPO_URL}"

    echo "Pushing to Git repository..."
    git push -u origin master

    if [ $? -ne 0 ]; then
        echo "Error: Failed to push to Git repository."
        exit 1
    fi

    echo "Successfully synced ${chart_name} to Git repository."
}

# Main execution
main() {
    if [ $# -ne 2 ]; then
        echo "Usage: $0 <chart_name> <chart_version>"
        exit 1
    fi

    local chart_name=$1
    local chart_version=$2

    download_helm_chart "${chart_name}" "${chart_version}"
    unzip_helm_chart "${chart_name}-${chart_version}.tgz"
    sync_to_git "${chart_name}"

    echo "Helm chart successfully synced to Git repository."
}

# Run the script
main "$@"

