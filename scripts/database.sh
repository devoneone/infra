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

# Function to set database-specific configurations
configure_database() {
    case ${DB_TYPE} in
        "mysql")
            DB_IMAGE="mysql:${DB_VERSION}"
            ENV_ROOT_PASSWORD_VAR="MYSQL_ROOT_PASSWORD"
            ENV_USERNAME_VAR="MYSQL_USER"
            ENV_PASSWORD_VAR="MYSQL_PASSWORD"
            ENV_DB_VAR="MYSQL_DATABASE"
            DB_PORT=3306
            VOLUME_MOUNT_PATH="/var/lib/mysql"
            ;;
        "postgres")
            DB_IMAGE="postgres:${DB_VERSION}"
            ENV_USERNAME_VAR="POSTGRES_USER"
            ENV_PASSWORD_VAR="POSTGRES_PASSWORD"
            ENV_DB_VAR="POSTGRES_DB"
            DB_PORT=5432
            VOLUME_MOUNT_PATH="/var/lib/postgresql/data"
            ;;
        "mongodb")
            DB_IMAGE="mongo:${DB_VERSION}"
            ENV_USERNAME_VAR="MONGO_INITDB_ROOT_USERNAME"
            ENV_PASSWORD_VAR="MONGO_INITDB_ROOT_PASSWORD"
            ENV_DB_VAR="MONGO_INITDB_DATABASE"
            DB_PORT=27017
            VOLUME_MOUNT_PATH="/data/db"
            ;;
        *)
            echo "❌ Unsupported database type. Use postgres, mysql, or mongodb."
            exit 1
            ;;
    esac
}
