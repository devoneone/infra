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

    # Debug: Confirm file existence before upload
    if [[ ! -f "$file" ]]; then
        echo "Error: File $file does not exist. Cannot upload to Nexus."
        exit 1
    fi

    echo "Uploading $file to Nexus Helm repository: $NEXUS_URL"
    
    # Add verbose logging to curl
    curl -v -u "$NEXUS_USER:$NEXUS_PASS" \
         --upload-file "$file" \
         "$NEXUS_URL" || {
        echo "Error: Failed to upload $file to Nexus repository."
        exit 1
    }

    echo "Successfully uploaded $file to Nexus: $NEXUS_URL"
}

# Function to update the Helm chart version using the TAG
update_chart_version() {
    local chart_dir=$1
    local tag=$2

    echo "Updating chart version to match the provided tag: $tag"
    yq eval ".version = \"$tag\"" -i "$chart_dir/Chart.yaml"
    echo "Chart version updated to $tag"
}

# Check dependencies
check_dependencies() {
    for cmd in helm yq curl; do
        if ! command -v $cmd &> /dev/null; then
            echo "Error: '$cmd' is not installed. Please install it first."
            exit 1
        fi
    done
}

# Main script execution
main() {
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

    check_dependencies

    echo "Creating Helm chart: $CHART_NAME"
    helm create "$CHART_NAME"
    cd "$CHART_NAME" || { echo "Error: Failed to access $CHART_NAME directory."; exit 1; }

    # Update values.yaml
    echo "Updating values.yaml..."
    yq eval ".name = \"$CHART_NAME\"" -i values.yaml
    yq eval ".image.repository = \"$IMAGE\"" -i values.yaml
    yq eval ".image.tag = \"$TAG\"" -i values.yaml
    yq eval ".port = $PORT" -i values.yaml
    yq eval ".namespace = \"$NAMESPACE\"" -i values.yaml
    yq eval ".ingress.enabled = true" -i values.yaml
    yq eval ".ingress.hosts[0].host = \"$HOST\"" -i values.yaml

    # Update chart version using the provided TAG
    update_chart_version . "$TAG"

    echo "Updated values.yaml:"
    cat values.yaml

    # Package the Helm chart
    cd ..
    echo "Packaging Helm chart..."
    local chart_package="${CHART_NAME}-*.tgz"
    helm package "$CHART_NAME" || { echo "Error: Failed to package Helm chart."; exit 1; }

    echo "Looking for packaged file: $chart_package"
    ls -l $chart_package || { echo "Error: Packaged Helm chart not found."; exit 1; }

    # Upload to Nexus
    echo "Uploading Helm chart to Nexus..."
    upload_to_nexus $chart_package

    # Cleanup
    echo "Cleaning up..."
    rm -rf "$CHART_NAME"
    rm -f $chart_package
    echo "Cleanup completed. Script finished successfully."
}

# Run the script
main "$@"
