#!/bin/bash
# Input variables
DB_NAME=$1                  # Database name (required)
DB_TYPE=$2                  # Database type (required)
DB_VERSION=$3               # Database version (required)
NAMESPACE=$4                # Namespace (required)
DB_PASSWORD=$5              # Database password (required for MySQL)
DB_USERNAME=${6:-defaultUser} # Database username (default for MySQL)
DOMAIN_NAME=$7              # Optional domain name for Ingress
STORAGE_SIZE=${8:-1Gi}      # Default storage size
PORT=${9:-30000}           # Default port for NodePort

# Create namespace and secret
create_namespace_resources() {
    mkdir namespace
    kubectl create namespace ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -
    
    if [ "${DB_TYPE}" == "mysql" ]; then
        kubectl create secret generic ${DB_NAME}-secret \
            --from-literal=${ENV_ROOT_PASSWORD_VAR}=${DB_PASSWORD} \
            --from-literal=${ENV_USERNAME_VAR}=${DB_USERNAME} \
            --from-literal=${ENV_PASSWORD_VAR}=${DB_PASSWORD} \
            --from-literal=${ENV_DB_VAR}=${DB_NAME} \
            --namespace=${NAMESPACE} \
            --dry-run=client -o yaml | kubectl apply -f -
    else
        kubectl create secret generic ${DB_NAME}-secret \
            --from-literal=${ENV_USERNAME_VAR}=${DB_USERNAME} \
            --from-literal=${ENV_PASSWORD_VAR}=${DB_PASSWORD} \
            --from-literal=${ENV_DB_VAR}=${DB_NAME} \
            --namespace=${NAMESPACE} \
            --dry-run=client -o yaml | kubectl apply -f -
    fi
}