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
PORT=${9:-30000}            # Default port for NodePort

# Validate required parameters
if [ -z "$DB_NAME" ] || [ -z "$DB_TYPE" ] || [ -z "$DB_VERSION" ] || [ -z "$NAMESPACE" ]; then
    echo "❌ Error: Missing required parameters"
    echo "Usage: $0 DB_NAME DB_TYPE DB_VERSION NAMESPACE [DB_PASSWORD] [DB_USERNAME] [DOMAIN_NAME] [STORAGE_SIZE] [PORT]"
    exit 1
fi

# Set MySQL-specific defaults
if [ "${DB_TYPE}" == "mysql" ]; then
    DB_PASSWORD=${DB_PASSWORD:-rootpassword}
    DB_USERNAME=${DB_USERNAME:-defaultuser}
fi

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

# Create namespace and secret
create_namespace_resources() {
    echo "Creating namespace '${NAMESPACE}'..."
    if kubectl create namespace ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -; then
        echo "✅ Namespace '${NAMESPACE}' created successfully."
    else
        echo "❌ Error: Failed to create namespace '${NAMESPACE}'."
        exit 1
    fi

    echo "Creating secret for database credentials..."
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

    if [ $? -eq 0 ]; then
        echo "✅ Secret '${DB_NAME}-secret' created successfully."
    else
        echo "❌ Error: Failed to create secret."
        exit 1
    fi
}

# Create StorageClass
create_storage_class() {
    echo "Creating StorageClass 'local-storage'..."
    if ! kubectl get storageclass local-storage &>/dev/null; then
        cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: local-storage
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Retain
EOF
        if [ $? -eq 0 ]; then
            echo "✅ StorageClass 'local-storage' created successfully."
        else
            echo "❌ Error: Failed to create StorageClass."
            exit 1
        fi
    else
        echo "ℹ️ StorageClass 'local-storage' already exists. Skipping."
    fi
}

# Initialize host directory
initialize_host_directory() {
    echo "Initializing host directory '/data/${NAMESPACE}/${DB_NAME}'..."
    sudo mkdir -p /data/${NAMESPACE}/${DB_NAME}
    sudo chown -R 999:999 /data/${NAMESPACE}/${DB_NAME}
    sudo chmod -R 700 /data/${NAMESPACE}/${DB_NAME}
    if [ $? -eq 0 ]; then
        echo "✅ Host directory initialized successfully."
    else
        echo "❌ Error: Failed to initialize host directory."
        exit 1
    fi
}

# Create PV
create_persistent_volume() {
    echo "Creating PersistentVolume for '${DB_NAME}'..."
    NODE_NAME=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolume
metadata:
  name: ${NAMESPACE}-${DB_NAME}-pv
  labels:
    type: database
    app: ${DB_NAME}
    namespace: ${NAMESPACE}
spec:
  capacity:
    storage: ${STORAGE_SIZE}
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: local-storage
  hostPath:
    path: /data/${NAMESPACE}/${DB_NAME}
    type: DirectoryOrCreate
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - ${NODE_NAME}
EOF

    if [ $? -eq 0 ]; then
        echo "✅ PersistentVolume created successfully."
    else
        echo "❌ Error: Failed to create PersistentVolume."
        exit 1
    fi
}
validate_k8s_environment() {
    echo "Validating Kubernetes environment..."
    if ! command -v kubectl &>/dev/null; then
        echo "❌ kubectl is not installed or not in PATH. Please install it first."
        exit 1
    fi

    if ! kubectl version --client &>/dev/null; then
        echo "❌ Unable to connect to the Kubernetes cluster. Ensure kubectl is configured correctly."
        exit 1
    fi

    echo "✅ Kubernetes environment validated."
}

create_persistent_volume_claim() {
    echo "Creating PersistentVolumeClaim..."
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${DB_NAME}-pvc
  namespace: ${NAMESPACE}
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: ${DB_STORAGE}
  storageClassName: ${STORAGE_CLASS}
EOF
    echo "✅ PersistentVolumeClaim created."
}
create_statefulset() {
    echo "Creating StatefulSet..."
    cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: ${DB_NAME}
  namespace: ${NAMESPACE}
spec:
  serviceName: ${DB_NAME}
  replicas: 1
  selector:
    matchLabels:
      app: ${DB_NAME}
  template:
    metadata:
      labels:
        app: ${DB_NAME}
    spec:
      containers:
      - name: ${DB_NAME}
        image: ${DB_IMAGE}
        ports:
        - containerPort: ${DB_PORT}
        env:
        $(if [ -n "${DB_ENV_VARS}" ]; then echo "${DB_ENV_VARS}"; fi)
        volumeMounts:
        - name: ${DB_NAME}-volume
          mountPath: ${VOLUME_MOUNT_PATH}
      volumes:
        - name: ${DB_NAME}-volume
          persistentVolumeClaim:
            claimName: ${DB_NAME}-pvc
EOF
    echo "✅ StatefulSet created."
}
create_service() {
    echo "Creating Service..."
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: ${DB_NAME}
  namespace: ${NAMESPACE}
spec:
  selector:
    app: ${DB_NAME}
  ports:
  - protocol: TCP
    port: ${DB_PORT}
    targetPort: ${DB_PORT}
  type: NodePort
EOF
    echo "✅ Service created."
}
create_ingress() {
    if [ -n "${INGRESS_HOST}" ]; then
        echo "Creating Ingress..."
        cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ${DB_NAME}-ingress
  namespace: ${NAMESPACE}
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  rules:
  - host: ${INGRESS_HOST}
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: ${DB_NAME}
            port:
              number: ${DB_PORT}
EOF
        echo "✅ Ingress created."
    else
        echo "⚠️ Ingress host not provided. Skipping Ingress creation."
    fi
}
collect_logs() {
    echo "Collecting logs for troubleshooting..."
    POD_NAME=$(kubectl get pods -n ${NAMESPACE} -l app=${DB_NAME} -o jsonpath='{.items[0].metadata.name}')
    if [ -n "$POD_NAME" ]; then
        kubectl logs $POD_NAME -n ${NAMESPACE} > ${DB_NAME}-logs.txt
        echo "Logs saved to ${DB_NAME}-logs.txt"
    else
        echo "❌ No pods found for ${DB_NAME}."
    fi
}

main() {
    configure_database
    validate_k8s_environment
    create_namespace_resources
    create_storage_class
    initialize_host_directory
    create_persistent_volume
    create_persistent_volume_claim
    create_statefulset
    create_service
    create_ingress
    check_deployment_status
    collect_logs
}


main
