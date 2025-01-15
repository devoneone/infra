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

# Create Service
create_service() {
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: ${DB_NAME}
  namespace: ${NAMESPACE}
  labels:
    app: ${DB_NAME}
    type: database
spec:
  type: NodePort
  ports:
    - port: ${DB_PORT}
      targetPort: ${DB_PORT}
      protocol: TCP
      name: db-port
      nodePort: ${PORT}
  selector:
    app: ${DB_NAME}
    type: database
EOF
}