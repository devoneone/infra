#!/bin/bash

set -euo pipefail

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
GITLAB_API_URL="https://git.shinoshike.studio/api/v4/projects"
GITLAB_TOKEN=${GITLAB_TOKEN:-"glpat-xBEAzy-73hWdWatMxCqd"}
NAMESPACE_ID=44
VISIBILITY="public"
ARGOCD_SERVER="argocd.soben.me"
ARGOCD_APP_NAME="${CHART_NAME}"
ARGOCD_USERNAME="admin"
ARGOCD_PASSWORD=${ARGOCD_PASSWORD:-"2eo10JZVXDr5CVba"}

# Logging function
log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Install tools
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

  # Pull the Helm chart archive
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

    # Ensure the script has permissions to modify the directory
    if [ ! -w "$CHART_NAME" ]; then
      log "ERROR: Insufficient permissions to modify directory: $CHART_NAME"
      exit 1
    fi

    # Remove specific files and directories with proper error handling
    rm -f "$CHART_NAME/.helmignore" "$CHART_NAME/Chart.yaml" "$CHART_NAME/values.yaml" 2>/dev/null || {
      log "ERROR: Failed to remove files in $CHART_NAME. Check permissions."
      exit 1
    }
    rm -rf "$CHART_NAME/templates" 2>/dev/null || {
      log "ERROR: Failed to remove templates directory. Check permissions."
      exit 1
    }

    # Extract chart files
    tar -zxvf $CHART_FILE -C "$CHART_NAME" --strip-components=1 || {
      log "ERROR: Failed to extract Helm chart files."
      exit 1
    }
  else
    mkdir -p "$CHART_NAME" || {
      log "ERROR: Failed to create directory $CHART_NAME. Check permissions."
      exit 1
    }
    tar -zxvf $CHART_FILE -C "$CHART_NAME" --strip-components=1 || {
      log "ERROR: Failed to extract Helm chart files."
      exit 1
    }
  fi

  # Clean up the Helm chart archive
  log "INFO: Cleaning up Helm chart archive: $CHART_FILE"
  rm -f $CHART_FILE || {
    log "ERROR: Failed to remove Helm chart archive: $CHART_FILE"
    exit 1
  }

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
  log "INFO: .git directory exists. Adding and pushing changes."
  git add .
  git commit -m "Update Helm chart"
  git push
else
  log "INFO: .git directory missing or corrupted. Reinitializing repository."
  git init
  git branch -M main
  git remote add origin "$SSH_REPO"
  git add .
  git commit -m "Initial commit"
  git push -u origin main
fi


  log "INFO: Helm chart pushed successfully."
  cd ..
}


# Create ArgoCD application
create_argocd_app() {

  log "INFO: Creating ArgoCD application $ARGOCD_APP_NAME..."
cat <<EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: $ARGOCD_APP_NAME-argocd
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://git.shinoshike.studio/argocd/$ARGOCD_APP_NAME.git
    targetRevision: main
    path: ./ # Adjust if the manifests are located in a subdirectory
  destination:
    server: https://kubernetes.default.svc
    namespace: default
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
EOF

  log "INFO: ArgoCD application $ARGOCD_APP_NAME created successfully."
}

# Synchronize with ArgoCD
sync_with_argocd() {
  log "INFO: Logging in to ArgoCD..."
  argocd login $ARGOCD_SERVER --username $ARGOCD_USERNAME --password $ARGOCD_PASSWORD --insecure --grpc-web

  log "INFO: Synchronizing application $ARGOCD_APP_NAME with ArgoCD..."
  argocd app sync $ARGOCD_APP_NAME || log "INFO: ArgoCD synchronization skipped as application is up to date."

  log "INFO: ArgoCD synchronization complete."
}

# Main script execution
main() {
  install_tools
  add_helm_repo
  pull_and_extract_chart
  check_gitlab_repo
  push_to_gitlab
  create_argocd_app
  sync_with_argocd
  log "INFO: Script completed successfully."
}

main
