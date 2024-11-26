#!/bin/bash

# Configuration
NEXUS_URL="https://nex.psa-khmer.world/repository/helm-store/" # Nexus Helm repo URL
NEXUS_USER="admin" # Nexus username
NEXUS_PASS="admin" # Nexus password

# Function to install yq
install_yq() {
    echo "Installing 'yq'..."
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        curl -L "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64" -o /usr/local/bin/yq
        chmod +x /usr/local/bin/yq
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        brew install yq || { echo "Error: Homebrew is not installed. Install Homebrew first."; exit 1; }
    else
        echo "Unsupported OS. Please install 'yq' manually from https://github.com/mikefarah/yq"
        exit 1
    fi
    echo "'yq' installed successfully."
}

# Function to upload chart to Nexus
upload_to_nexus() {
    local file=$1
    echo "Uploading $file to Nexus Helm repository..."
    curl -u "$NEXUS_USER:$NEXUS_PASS" --upload-file "$file" "$NEXUS_URL" || {
        echo "Error: Failed to upload $file to Nexus repository."
        exit 1
    }
    echo "Successfully uploaded $file to Nexus."
}

# Check dependencies
check_dependencies() {
    if ! command -v yq &> /dev/null; then
        echo "'yq' is not installed."
        install_yq
    fi

    for cmd in helm zip curl; do
        if ! command -v $cmd &> /dev/null; then
            echo "Error: '$cmd' is not installed. Please install it first."
            exit 1
        fi
    done
}

# Main script execution
main() {
    # Validate input
    if [[ $# -lt 5 ]]; then
        echo "Usage: $0 <CHART_NAME> <IMAGE> <TAG> <PORT> <NAMESPACE> [HOST]"
        exit 1
    fi

    local CHART_NAME=$1
    local IMAGE=$2
    local TAG=$3
    local PORT=$4
    local NAMESPACE=$5
    local HOST=${6:-"example.com"} # Default ingress host

    # Ensure dependencies are installed
    check_dependencies

    # Create Helm chart
    helm create "$CHART_NAME"
    cd "$CHART_NAME" || { echo "Error: Failed to access $CHART_NAME directory."; exit 1; }

    # Update values.yaml
    yq eval ".name = \"$CHART_NAME\"" -i values.yaml
    yq eval ".image.repository = \"$IMAGE\"" -i values.yaml
    yq eval ".image.tag = \"$TAG\"" -i values.yaml
    yq eval ".port = \"$PORT\"" -i values.yaml
    yq eval ".namespace = \"$NAMESPACE\"" -i values.yaml
    yq eval ".ingress.enabled = true" -i values.yaml
    yq eval ".ingress.hosts[0].host = \"$HOST\"" -i values.yaml

    echo "Updated values.yaml:"
    cat values.yaml

    # Package the Helm chart
    cd ..
    helm package "$CHART_NAME" || { echo "Error: Failed to package Helm chart."; exit 1; }

    # Upload to Nexus
    local CHART_PACKAGE="${CHART_NAME}-*.tgz"
    upload_to_nexus "$CHART_PACKAGE"

    # Cleanup
    rm -f "$CHART_PACKAGE"
    echo "Cleanup completed. Script finished successfully."
}

# Run the script
main "$@"
