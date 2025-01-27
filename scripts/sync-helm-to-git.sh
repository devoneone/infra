#!/bin/bash

set -euo pipefail

# Validate input arguments
if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Usage: $0 <CHART_NAME> <CHART_VERSION>"
    exit 1
fi

# Assign input parameters
CHART_NAME="$1"
CHART_VERSION="$2"

# Other variables
REPO_NAME="helm-store"
REPO_URL="https://nex.psa-khmer.world/repository/helm-store/"
USERNAME="admin"
PASSWORD="admin"
CHART_FILE="${CHART_NAME}-${CHART_VERSION}.tgz"
GITLAB_API_URL="https://git.cloudinator.cloud/api/v4/projects"
GITLAB_TOKEN=${GITLAB_TOKEN:-"glpat-WXeK4PkToFK5vVx6qTZN"}
NAMESPACE_ID=123
VISIBILITY="public"
ARGOCD_SERVER="argo.cloudinator.cloud"
ARGOCD_APP_NAME="${CHART_NAME}"
ARGOCD_USERNAME="admin"
ARGOCD_PASSWORD=${ARGOCD_PASSWORD:-"usYKBEHJMoM92rTy"}
TARGET_DIR="/home/asura/cloudinator"

# Logging function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Install required tools
install_tools() {
    log "INFO: Checking if required tools are installed..."

    local tools=("jq" "helm" "argocd" "kubectl")

    for tool in "${tools[@]}"; do
        if ! command -v $tool &>/dev/null; then
            log "INFO: Installing $tool..."
            if command -v apt-get &>/dev/null; then
                sudo apt-get update && sudo apt-get install -y $tool
            elif command -v yum &>/dev/null; then
                sudo yum install -y $tool
            else
                log "ERROR: Unsupported package manager. Please install $tool manually." >&2
                exit 1
            fi
        fi
    done

    log "INFO: All required tools are installed."
}

# Add Helm repository and update
add_helm_repo() {
    log "INFO: Adding Helm repository: $REPO_NAME"

    if helm repo list | grep -q "$REPO_NAME"; then
        log "INFO: Repository $REPO_NAME already exists. Updating instead."
        helm repo update
        if [[ $? -ne 0 ]]; then
            log "ERROR: Failed to update Helm repository." >&2
            exit 1
        fi
    else
        helm repo add $REPO_NAME $REPO_URL --username $USERNAME --password $PASSWORD
        if [[ $? -ne 0 ]]; then
            log "ERROR: Failed to add Helm repository." >&2
            exit 1
        fi
    fi

    log "INFO: Helm repositories updated successfully."
}

# Pull and extract Helm chart
pull_and_extract_chart() {
    log "INFO: Pulling Helm chart: $CHART_NAME, version: $CHART_VERSION"

    # Navigate to target directory
    cd "$TARGET_DIR" || { log "ERROR: Failed to navigate to target directory: $TARGET_DIR"; exit 1; }

    # Pull the Helm chart archive if it doesn't exist
    if [ ! -f "$CHART_FILE" ]; then
        helm pull $REPO_NAME/$CHART_NAME --version $CHART_VERSION
    else
        log "INFO: Helm chart archive $CHART_FILE already exists. Overriding with new version."
        helm pull $REPO_NAME/$CHART_NAME --version $CHART_VERSION
    fi

    log "INFO: Extracting Helm chart..."

    # Check if the directory exists
    if [ -d "$CHART_NAME" ]; then
        log "INFO: Directory $CHART_NAME already exists. Removing specific files and folders."

        # Remove specific files and directories
        rm -f "$CHART_NAME/.helmignore" "$CHART_NAME/Chart.yaml" "$CHART_NAME/values.yaml"
        rm -rf "$CHART_NAME/templates"

        # Extract chart files
        tar -zxvf $CHART_FILE -C "$CHART_NAME" --strip-components=1
    else
        mkdir "$CHART_NAME"
        tar -zxvf $CHART_FILE -C "$CHART_NAME" --strip-components=1
    fi

    # Clean up the Helm chart archive
    log "INFO: Cleaning up Helm chart archive: $CHART_FILE"
    rm -f $CHART_FILE

    log "INFO: Helm chart pull and extraction completed."
}

# Check if GitLab repository exists
check_gitlab_repo() {
    log "INFO: Checking if GitLab repository for $CHART_NAME exists..."

    RESPONSE=$(curl -s -X GET "$GITLAB_API_URL?search=$CHART_NAME" \
        -H "Authorization: Bearer $GITLAB_TOKEN")

    if ! echo "$RESPONSE" | jq empty &>/dev/null; then
        log "ERROR: Invalid response from GitLab API. Response: $RESPONSE" >&2
        exit 1
    fi

    SSH_REPO=$(echo "$RESPONSE" | jq -r '.[] | select(.name == "'$CHART_NAME'") | .ssh_url_to_repo // empty')
    if [[ -n "$SSH_REPO" ]]; then
        log "INFO: GitLab repository already exists: $SSH_REPO"
    else
        log "INFO: GitLab repository does not exist. Attempting to create it..."
        create_gitlab_repo
    fi
}

# Create GitLab repository
create_gitlab_repo() {
    log "INFO: Creating GitLab repository for $CHART_NAME..."
    RESPONSE=$(curl -s -X POST "$GITLAB_API_URL" \
        -H "Authorization: Bearer $GITLAB_TOKEN" \
        -H "Content-Type: application/json" \
        -d '{
            "name": "'$CHART_NAME'",
            "namespace_id": '$NAMESPACE_ID',
            "visibility": "'$VISIBILITY'"
        }')

    SSH_REPO=$(echo "$RESPONSE" | jq -r '.ssh_url_to_repo')
    if [[ "$SSH_REPO" == "null" ]]; then
        ERROR_MSG=$(echo "$RESPONSE" | jq -r '.message // "Unknown error"')
        if [[ "$ERROR_MSG" == *"has already been taken"* ]]; then
            log "INFO: Repository already exists. Skipping creation."
        else
            log "ERROR: Failed to create GitLab repository: $ERROR_MSG" >&2
            exit 1
        fi
    fi

    log "INFO: GitLab repository created successfully: $SSH_REPO"
}

# Push chart to GitLab repository
push_to_gitlab() {
    log "INFO: Pushing Helm chart to GitLab repository..."
    cd "$CHART_NAME"

    if [ -d .git ]; then
        git add .
        git commit -m "Update Helm chart to version $CHART_VERSION" || log "INFO: No changes to commit."
        # Use GIT_ASKPASS to pass the token explicitly
        GIT_ASKPASS=$(mktemp)
        cat <<EOF > $GIT_ASKPASS
#!/bin/sh
echo ${GITLAB_TOKEN}
EOF
        chmod +x $GIT_ASKPASS

        GIT_ASKPASS=$GIT_ASKPASS git push -u origin main || { log "ERROR: Failed to push changes to GitLab." >&2; exit 1; }

        rm $GIT_ASKPASS
    else
        git init
        git branch -M main
        git remote add origin "https://git.cloudinator.cloud/argocd/$ARGOCD_APP_NAME.git"
        git add .
        git commit -m "Initial commit for Helm chart version $CHART_VERSION"

        # Use GIT_ASKPASS to pass the token explicitly
        GIT_ASKPASS=$(mktemp)
        cat <<EOF > $GIT_ASKPASS
#!/bin/sh
echo ${GITLAB_TOKEN}
EOF
        chmod +x $GIT_ASKPASS

        GIT_ASKPASS=$GIT_ASKPASS git push -u origin main || { log "ERROR: Failed to push changes to GitLab." >&2; exit 1; }

        rm $GIT_ASKPASS
    fi

    log "INFO: Helm chart pushed successfully."
    cd ..
}

# Create ArgoCD application with enhanced sync automation
create_argocd_app() {
    log "INFO: Creating ArgoCD application $ARGOCD_APP_NAME..."
    cat <<EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: $ARGOCD_APP_NAME-argocd
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "1"
    argocd.argoproj.io/sync-options: PrunePropagationPolicy=foreground
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://git.cloudinator.cloud/argocd/$ARGOCD_APP_NAME.git
    targetRevision: 'main'
    path: ./
  destination:
    server: https://kubernetes.default.svc
    namespace: $CHART_NAME
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
      allowEmpty: true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
    syncOptions:
      - CreateNamespace=true
      - PruneLast=true
      - PrunePropagationPolicy=foreground
      - RespectIgnoreDifferences=true
      - ApplyOutOfSyncOnly=true
EOF

    if [ $? -ne 0 ]; then
        log "ERROR: Failed to create ArgoCD application" >&2
        exit 1
    fi

    log "INFO: ArgoCD application $ARGOCD_APP_NAME created successfully."
}

# Enhanced sync with ArgoCD including status checking
force_sync_with_argocd() {
    local max_retries=5
    local retry_count=0
    local wait_time=10

    log "INFO: Logging in to ArgoCD..."
    argocd login $ARGOCD_SERVER --username $ARGOCD_USERNAME --password $ARGOCD_PASSWORD --insecure --grpc-web || {
        log "ERROR: Failed to login to ArgoCD" >&2
        exit 1
    }

    log "INFO: Waiting for application to be registered in ArgoCD..."
    while ! argocd app get $ARGOCD_APP_NAME-argocd &>/dev/null; do
        sleep 5
        ((retry_count++))
        if [ $retry_count -ge $max_retries ]; then
            log "ERROR: Timeout waiting for application to be registered" >&2
            exit 1
        fi
    done

    log "INFO: Initiating sync process..."
    argocd app sync $ARGOCD_APP_NAME-argocd --async || {
        log "ERROR: Failed to initiate sync" >&2
        exit 1
    }

    # Wait for sync to complete
    retry_count=0
    while true; do
        status=$(argocd app get $ARGOCD_APP_NAME-argocd -o json | jq -r '.status.sync.status')
        health=$(argocd app get $ARGOCD_APP_NAME-argocd -o json | jq -r '.status.health.status')
        
        log "INFO: Current status - Sync: $status, Health: $health"
        
        if [ "$status" = "Synced" ] && [ "$health" = "Healthy" ]; then
            log "INFO: Application successfully synced and healthy"
            break
        fi
        
        if [ "$status" = "Unknown" ] || [ "$health" = "Degraded" ]; then
            log "WARNING: Application health check failed, attempting retry..."
            argocd app sync $ARGOCD_APP_NAME-argocd --async
        fi
        
        ((retry_count++))
        if [ $retry_count -ge $max_retries ]; then
            log "ERROR: Max retries reached. Please check application status manually" >&2
            exit 1
        fi
        
        log "INFO: Waiting $wait_time seconds before next check..."
        sleep $wait_time
    done

    log "INFO: ArgoCD sync completed successfully"
}

# Function to cleanup on script exit
cleanup() {
    if [ -n "${ARGOCD_TOKEN:-}" ]; then
        argocd logout $ARGOCD_SERVER || true
    fi
}

# Register cleanup function
trap cleanup EXIT

# Main script execution
main() {
    install_tools
    add_helm_repo
    pull_and_extract_chart
    check_gitlab_repo
    push_to_gitlab
    create_argocd_app
    force_sync_with_argocd
    log "INFO: Script completed successfully."
}

main
