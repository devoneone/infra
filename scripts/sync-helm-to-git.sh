#!/bin/bash

# Set variables
REPO_NAME="helm-store"
REPO_URL="https://nex.psa-khmer.world/repository/helm-store/"
USERNAME="admin"
PASSWORD="admin"
CHART_NAME="cloudinator-app"
CHART_VERSION="134"
CHART_FILE="${CHART_NAME}-${CHART_VERSION}.tgz"
GITLAB_API_URL="https://git.shinoshike.studio/api/v4/projects"
GITLAB_TOKEN="glpat-xBEAzy-73hWdWatMxCqd"
PROJECT_NAME="this is my name"
NAMESPACE_ID=44
VISIBILITY="public"

# Add the Nexus Helm repository
echo "Adding Helm repository: $REPO_NAME"
helm repo add $REPO_NAME $REPO_URL --username $USERNAME --password $PASSWORD

# Update Helm repositories
echo "Updating Helm repositories..."
helm repo update

# Pull the specified Helm chart
echo "Pulling Helm chart: $CHART_NAME, version: $CHART_VERSION"
helm pull $REPO_NAME/$CHART_NAME --version $CHART_VERSION

# Extract the Helm chart
echo "Extracting Helm chart..."
tar -zxvf $CHART_FILE

# Remove the .tgz file after extraction
echo "Removing the .tgz file: $CHART_FILE"
rm -f $CHART_FILE

# Change directory to the extracted chart
cd ${CHART_NAME}-${CHART_VERSION}

# List the contents of the extracted chart
echo "Listing contents of the extracted chart directory:"
ll

# Create a project in GitLab using the API
echo "Creating a project in GitLab..."
REPO_RESPONSE=$(curl --silent --request POST \
  --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
  --data "name=$PROJECT_NAME&namespace_id=$NAMESPACE_ID&visibility=$VISIBILITY" \
  "$GITLAB_API_URL")

# Extract the GitLab repository URL from the response
REPO_URL=$(echo $REPO_RESPONSE | jq -r '.ssh_url_to_repo')
if [ "$REPO_URL" == "null" ]; then
  echo "Failed to create GitLab project. Response: $REPO_RESPONSE"
  exit 1
fi
echo "GitLab repository created: $REPO_URL"

# Initialize a Git repository
echo "Initializing Git repository..."
git init

# Add a remote pointing to the GitLab repository
echo "Adding remote Git repository..."
git remote add origin $REPO_URL

# Create a `main` branch and make the initial commit
echo "Setting up main branch and making the initial commit..."
git branch -M main
git add .
git commit -m "Initial commit"

# Push the code to the newly created GitLab repository
echo "Pushing code to the remote repository..."
git push -u origin main

# End of script
echo "Helm chart $CHART_NAME version $CHART_VERSION has been pulled, extracted, added to Git, and pushed to $REPO_URL successfully."
