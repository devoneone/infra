#!/bin/bash

set -euo pipefail

# Variables
project_name=$1
group=$2
folder_name=$3
gitlab_token=$4   # GitLab token passed as parameter
group_id=$5       # Group ID passed as parameter
service_name=${6:-}  # Optional array of services name parameter
dependencies_input=${7:-}

# Configuration for external services
JENKINS_URL="http://34.142.187.195:8080"
JENKINS_USER="asura"
JENKINS_API_TOKEN="11cae77a9e032f7f2ebd9b82e75aeb087e"
GITLAB_URL="https://git.shinoshike.studio/"

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Error message for missing dependency
error_exit() {
    echo "$1" 1>&2
    exit 1
}

# Check if required tools are installed
for cmd in gradle git curl; do
    command_exists "$cmd" || error_exit "$cmd is not installed. Please install it."
done

# Helper functions
to_camel_case() {
    echo "$1" | sed -E 's/(^|-)([a-z])/\U\2/g'
}

# Process project variables
project_name_lower=$(echo "$project_name" | sed -E 's/([a-z0-9])([A-Z])/\1-\2/g' | tr '[:upper:]' '[:lower:]')
SERVICE_NAME="$project_name_lower"
project_name_camel=$(to_camel_case "$project_name")
main_class="${project_name_camel}Application"
package_path=$(echo "$group" | tr '.' '/')

# Process dependencies
default_dependencies="
    implementation 'org.springframework.boot:spring-boot-starter'
    implementation 'org.springframework.boot:spring-boot-starter-web'
    testImplementation 'org.springframework.boot:spring-boot-starter-test'
"

dynamic_dependencies=""
if [[ -n "$dependencies_input" ]]; then
    if [[ -f "$dependencies_input" ]]; then
        # Read dependencies from file
        while IFS= read -r line; do
            dynamic_dependencies="${dynamic_dependencies}\n    ${line}"
        done < "$dependencies_input"
    else
        # Add single dependency passed as an argument
        dynamic_dependencies="    $dependencies_input"
    fi
fi

all_dependencies="${default_dependencies}${dynamic_dependencies}"

# Function to create project structure
create_project() {
    local project_name_lower=$1
    local main_class=$2

    project_dir="${project_name_lower}"
    src_dir="${project_dir}/src/main/java/${package_path}/${project_name_lower//-/}"

    mkdir -p "$src_dir"

    # Create build.gradle
    cat << EOF > "${project_dir}/build.gradle"
plugins {
    id 'org.springframework.boot' version '3.1.3'
    id 'io.spring.dependency-management' version '1.1.3'
    id 'java'
}

group = '${group}'
version = '0.0.1-SNAPSHOT'
sourceCompatibility = '17'

repositories {
    mavenCentral()
}

dependencies {
    ${all_dependencies}
}

tasks.named('test') {
    useJUnitPlatform()
}
EOF

    # Create main application class
    cat << EOF > "${src_dir}/${main_class}.java"
package ${group}.${project_name_lower//-/};

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication
public class ${main_class} {
    public static void main(String[] args) {
        SpringApplication.run(${main_class}.class, args);
    }
}
EOF

    # Create application.yml configuration
    mkdir -p "${project_dir}/src/main/resources"
    cat << EOF > "${project_dir}/src/main/resources/application.yml"
spring:
  application:
    name: ${project_name_lower}
EOF
}

# Function to create GitLab repository
create_gitlab_repo() {
    local repo_name=$1

    response=$(curl -s -X POST "${GITLAB_URL}/api/v4/projects" \
        --header "PRIVATE-TOKEN: $gitlab_token" \
        --header "Content-Type: application/json" \
        --data "{
            \"name\": \"${repo_name}\",
            \"namespace_id\": ${group_id},
            \"visibility\": \"public\"
        }")

    echo "$response" | jq -r ".http_url_to_repo"
}

# Function to create Jenkins job
create_jenkins_job() {
    local folder_name=$1
    local job_name=$2
    local project_name_lower=$3
    local service_names_input=$service_name  # Use passed service names

    # Process the service_name parameter into an array
    IFS=',' read -ra service_names_array <<< "$service_names_input"
    local dependencies_list=""
    for service in "${service_names_array[@]}"; do
        dependencies_list+=" '${service}',"
    done
    dependencies_list="${dependencies_list%,}" # Remove trailing comma

    local job_name_with_prefix="${job_name}-pipeline"

    # Jenkins pipeline script with variable substitution
    local pipeline_script=$(cat <<EOF
@Library('cloudinator-microservices') _

def DEPENDENCIES = [${dependencies_list}]

pipeline {
    agent any
    environment {
        SERVICE_NAME = '${SERVICE_NAME}'
        DOCKER_CREDENTIALS_ID = 'docker'
        GIT_REPO_URL = '${repo_url}'
        GIT_INFRA_URL = 'https://github.com/devoneone/micro-services-infra.git'
        INVENTORY_FILE = 'inventory/inventory.ini'
        PLAYBOOK_FILE = 'playbooks/deploy-microservice.yml'
        HELM_FILE = "playbooks/setup-helm-microservice.yml"
        ARGO_FILE = 'playbooks/synx-argocd.yml'
        NAMESPACE = '${folder_name}'
        EMAIL = "your-email@example.com"
        TRIVY_SEVERITY = "HIGH,CRITICAL"
        TRIVY_EXIT_CODE = "0"
        TRIVY_IGNORE_UNFIXED = "true"
        VULN_THRESHOLD = "5"
        DOCKER_IMAGE_NAME = "sovanra/\${SERVICE_NAME}"
        DOCKER_IMAGE_TAG = "\${BUILD_NUMBER}"
    }
    stages {
        stage('Check Dependencies') {
            steps {
                script {
                    checkDependencies(DEPENDENCIES, '${folder_name}')
                }
            }
        }
        stage('Checkout') {
            steps {
                git branch: 'main', url: env.GIT_REPO_URL
            }
        }
        stage('Build Docker Image') {
            steps {
                script {
                    dockerBuild("\${DOCKER_IMAGE_NAME}", "\${DOCKER_IMAGE_TAG}")
                }
            }
        }
        stage('Push Image to Registry') {
            steps {
                script {
                    dockerPush("\${DOCKER_IMAGE_NAME}", "\${DOCKER_IMAGE_TAG}")
                }
            }
        }
        stage('Deploy to Kubernetes') {
            steps {
                script {
                    deployToKubernetes(
                        INVENTORY_FILE,
                        PLAYBOOK_FILE,
                        SERVICE_NAME,
                        "\${DOCKER_IMAGE_NAME}:\${DOCKER_IMAGE_TAG}",
                        NAMESPACE,
                        "deployments/\${SERVICE_NAME}",
                        "\${SERVICE_NAME}.your-domain.com",
                        EMAIL,
                        GIT_REPO_URL
                    )
                }
            }
        }
        stage('Sync ArgoCD') {
            steps {
                syncArgoCD(
                    INVENTORY_FILE,
                    ARGO_FILE,
                    APP_NAME,
                    DOCKER_IMAGE_TAG
                )
            }
        }
    }
}
EOF
)

    # Jenkins job config XML
    local job_config_xml=$(cat <<EOF
<?xml version='1.1' encoding='UTF-8'?>
<flow-definition plugin="workflow-job">
  <actions/>
  <description>Spring Eureka Server Pipeline</description>
  <keepDependencies>false</keepDependencies>
  <properties/>
  <definition class="org.jenkinsci.plugins.workflow.cps.CpsFlowDefinition" plugin="workflow-cps">
    <script><![CDATA[${pipeline_script}]]></script>
    <sandbox>true</sandbox>
  </definition>
  <triggers/>
  <disabled>false</disabled>
</flow-definition>
EOF
)

    # Create Jenkins job via API
    curl -X POST "${JENKINS_URL}/job/${folder_name}/createItem?name=${job_name_with_prefix}" \
        --user "${JENKINS_USER}:${JENKINS_API_TOKEN}" \
        -H "Content-Type: application/xml" \
        --data-raw "${job_config_xml}" || error_exit "Failed to create Jenkins job in folder ${folder_name}"
}


# Main script execution
create_project "${project_name_lower}" "${main_class}"

# Initialize Git and push to GitLab
cd "${project_name_lower}"
git init
repo_url=$(create_gitlab_repo "${project_name_lower}")

# Embed the GitLab token into the repository URL for authentication
authenticated_repo_url=$(echo "${repo_url}" | sed "s|https://|https://${gitlab_token}@|")

git remote add origin "${authenticated_repo_url}"
git branch -M main
git add .
git commit -m "Initial commit"

# Use GIT_ASKPASS to pass the token explicitly
GIT_ASKPASS=$(mktemp)
cat <<EOF > $GIT_ASKPASS
#!/bin/sh
echo ${gitlab_token}
EOF
chmod +x $GIT_ASKPASS

GIT_ASKPASS=$GIT_ASKPASS git push -u origin main

rm $GIT_ASKPASS

# Cleanup project files after initializing repository
cd ..
rm -rf "${project_name_lower}"

create_jenkins_job "${folder_name}" "${project_name_lower}" "${project_name_lower}"

echo "Project setup completed successfully!"
