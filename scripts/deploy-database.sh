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

# Create the StorageClass
create_storage_class() {
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
    fi
}

# Initialize host directory
initialize_host_directory() {
    sudo mkdir -p /data/${NAMESPACE}/${DB_NAME}
    sudo chown -R 999:999 /data/${NAMESPACE}/${DB_NAME}
    sudo chmod -R 700 /data/${NAMESPACE}/${DB_NAME}
}

# Create PV
create_persistent_volume() {
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
}

# Create PVC
create_persistent_volume_claim() {
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${DB_NAME}-pvc
  namespace: ${NAMESPACE}
spec:
  storageClassName: local-storage
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: ${STORAGE_SIZE}
  selector:
    matchLabels:
      type: database
      app: ${DB_NAME}
      namespace: ${NAMESPACE}
EOF
}

# Create StatefulSet
create_statefulset() {
    if [ "${DB_TYPE}" == "mysql" ]; then
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
      type: database
  template:
    metadata:
      labels:
        app: ${DB_NAME}
        type: database
    spec:
      securityContext:
        fsGroup: 999
        runAsUser: 999
        runAsGroup: 999
      containers:
      - name: ${DB_NAME}
        image: ${DB_IMAGE}
        imagePullPolicy: IfNotPresent
        securityContext:
          allowPrivilegeEscalation: false
          runAsUser: 999
          runAsGroup: 999
          capabilities:
            drop: ["ALL"]
        env:
        - name: MYSQL_ROOT_PASSWORD
          valueFrom:
            secretKeyRef:
              name: ${DB_NAME}-secret
              key: MYSQL_ROOT_PASSWORD
        - name: MYSQL_USER
          valueFrom:
            secretKeyRef:
              name: ${DB_NAME}-secret
              key: MYSQL_USER
        - name: MYSQL_PASSWORD
          valueFrom:
            secretKeyRef:
              name: ${DB_NAME}-secret
              key: MYSQL_PASSWORD
        - name: MYSQL_DATABASE
          valueFrom:
            secretKeyRef:
              name: ${DB_NAME}-secret
              key: MYSQL_DATABASE
        ports:
        - name: db-port
          containerPort: ${DB_PORT}
          protocol: TCP
        volumeMounts:
        - name: data
          mountPath: ${VOLUME_MOUNT_PATH}
        resources:
          requests:
            memory: "256Mi"
            cpu: "200m"
          limits:
            memory: "512Mi"
            cpu: "500m"
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: ${DB_NAME}-pvc
EOF
    else
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
      type: database
  template:
    metadata:
      labels:
        app: ${DB_NAME}
        type: database
    spec:
      securityContext:
        fsGroup: 999
        runAsUser: 999
        runAsGroup: 999
      containers:
      - name: ${DB_NAME}
        image: ${DB_IMAGE}
        imagePullPolicy: IfNotPresent
        securityContext:
          allowPrivilegeEscalation: false
          runAsUser: 999
          runAsGroup: 999
          capabilities:
            drop: ["ALL"]
        env:
        - name: ${ENV_USERNAME_VAR}
          valueFrom:
            secretKeyRef:
              name: ${DB_NAME}-secret
              key: ${ENV_USERNAME_VAR}
        - name: ${ENV_PASSWORD_VAR}
          valueFrom:
            secretKeyRef:
              name: ${DB_NAME}-secret
              key: ${ENV_PASSWORD_VAR}
        - name: ${ENV_DB_VAR}
          valueFrom:
            secretKeyRef:
              name: ${DB_NAME}-secret
              key: ${ENV_DB_VAR}
        ports:
        - name: db-port
          containerPort: ${DB_PORT}
          protocol: TCP
        volumeMounts:
        - name: data
          mountPath: ${VOLUME_MOUNT_PATH}
        resources:
          requests:
            memory: "256Mi"
            cpu: "200m"
          limits:
            memory: "512Mi"
            cpu: "500m"
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: ${DB_NAME}-pvc
EOF
    fi
}

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

# Create Ingress
create_ingress() {
    if [ ! -z "${DOMAIN_NAME}" ]; then
        cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ${DB_NAME}-ingress
  namespace: ${NAMESPACE}
  annotations:
    kubernetes.io/ingress.class: nginx
    cert-manager.io/cluster-issuer: "letsencrypt-cloudflare"
    nginx.ingress.kubernetes.io/backend-protocol: "TCP"
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
    nginx.ingress.kubernetes.io/ssl-passthrough: "true"
spec:
  rules:
  - host: ${DOMAIN_NAME}
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: ${DB_NAME}
            port:
              number: ${DB_PORT}
  tls:
  - hosts:
    - ${DOMAIN_NAME}
    secretName: ${DB_NAME}-tls
EOF
    fi
}

# Function to create monitoring configurations
create_monitoring_config() {
    # Create configmap for exporters configuration
    case ${DB_TYPE} in
        "mysql")
            create_mysql_monitoring
            ;;
        "postgres")
            create_postgres_monitoring
            ;;
        "mongodb")
            create_mongodb_monitoring
            ;;
    esac

    # Create ServiceMonitor
    create_service_monitor
}

# MySQL monitoring configuration
create_mysql_monitoring() {
    cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${DB_NAME}-mysqld-exporter
  namespace: ${NAMESPACE}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ${DB_NAME}-mysqld-exporter
  template:
    metadata:
      labels:
        app: ${DB_NAME}-mysqld-exporter
    spec:
      containers:
      - name: mysqld-exporter
        image: prom/mysqld-exporter:v0.14.0
        args:
        - --collect.info_schema.tables
        - --collect.info_schema.tablestats
        - --collect.global_status
        - --collect.global_variables
        - --collect.slave_status
        - --collect.info_schema.processlist
        ports:
        - name: metrics
          containerPort: 9104
        env:
        - name: DATA_SOURCE_NAME
          valueFrom:
            secretKeyRef:
              name: ${DB_NAME}-monitoring-secret
              key: DATA_SOURCE_NAME
---
apiVersion: v1
kind: Service
metadata:
  name: ${DB_NAME}-mysqld-exporter
  namespace: ${NAMESPACE}
  labels:
    app: ${DB_NAME}-mysqld-exporter
spec:
  ports:
  - name: metrics
    port: 9104
    targetPort: metrics
  selector:
    app: ${DB_NAME}-mysqld-exporter
EOF

    # Create secret for mysqld-exporter
    kubectl create secret generic ${DB_NAME}-monitoring-secret \
        --namespace=${NAMESPACE} \
        --from-literal=DATA_SOURCE_NAME="${DB_USERNAME}:${DB_PASSWORD}@(${DB_NAME}:3306)/" \
        --dry-run=client -o yaml | kubectl apply -f -
}

# PostgreSQL monitoring configuration
create_postgres_monitoring() {
    # Deploy postgres-exporter
    cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${DB_NAME}-postgres-exporter
  namespace: ${NAMESPACE}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ${DB_NAME}-postgres-exporter
  template:
    metadata:
      labels:
        app: ${DB_NAME}-postgres-exporter
    spec:
      containers:
      - name: postgres-exporter
        image: prometheuscommunity/postgres-exporter:v0.11.1
        ports:
        - name: metrics
          containerPort: 9187
        env:
        - name: DATA_SOURCE_NAME
          valueFrom:
            secretKeyRef:
              name: ${DB_NAME}-monitoring-secret
              key: DATA_SOURCE_NAME
---
apiVersion: v1
kind: Service
metadata:
  name: ${DB_NAME}-postgres-exporter
  namespace: ${NAMESPACE}
  labels:
    app: ${DB_NAME}-postgres-exporter
spec:
  ports:
  - name: metrics
    port: 9187
    targetPort: metrics
  selector:
    app: ${DB_NAME}-postgres-exporter
EOF

    # Create secret for postgres-exporter
    kubectl create secret generic ${DB_NAME}-monitoring-secret \
        --namespace=${NAMESPACE} \
        --from-literal=DATA_SOURCE_NAME="postgresql://${DB_USERNAME}:${DB_PASSWORD}@${DB_NAME}:5432/${DB_NAME}?sslmode=disable" \
        --dry-run=client -o yaml | kubectl apply -f -
}

# MongoDB monitoring configuration
create_mongodb_monitoring() {
    # Deploy mongodb-exporter
    cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${DB_NAME}-mongodb-exporter
  namespace: ${NAMESPACE}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ${DB_NAME}-mongodb-exporter
  template:
    metadata:
      labels:
        app: ${DB_NAME}-mongodb-exporter
    spec:
      containers:
      - name: mongodb-exporter
        image: percona/mongodb_exporter:0.34
        ports:
        - name: metrics
          containerPort: 9216
        env:
        - name: MONGODB_URI
          valueFrom:
            secretKeyRef:
              name: ${DB_NAME}-monitoring-secret
              key: MONGODB_URI
---
apiVersion: v1
kind: Service
metadata:
  name: ${DB_NAME}-mongodb-exporter
  namespace: ${NAMESPACE}
  labels:
    app: ${DB_NAME}-mongodb-exporter
spec:
  ports:
  - name: metrics
    port: 9216
    targetPort: metrics
  selector:
    app: ${DB_NAME}-mongodb-exporter
EOF

    # Create secret for mongodb-exporter
    kubectl create secret generic ${DB_NAME}-monitoring-secret \
        --namespace=${NAMESPACE} \
        --from-literal=MONGODB_URI="mongodb://${DB_USERNAME}:${DB_PASSWORD}@${DB_NAME}:27017/${DB_NAME}" \
        --dry-run=client -o yaml | kubectl apply -f -
}

# Create ServiceMonitor for Prometheus Operator
create_service_monitor() {
    local EXPORTER_NAME="${DB_NAME}-${DB_TYPE}-exporter"
    local METRICS_PORT
    
    case ${DB_TYPE} in
        "mysql")
            METRICS_PORT=9104
            ;;
        "postgres")
            METRICS_PORT=9187
            ;;
        "mongodb")
            METRICS_PORT=9216
            ;;
    esac

    cat <<EOF | kubectl apply -f -
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: ${DB_NAME}-monitor
  namespace: ${NAMESPACE}
  labels:
    release: prometheus
spec:
  endpoints:
  - interval: 30s
    port: metrics
    path: /metrics
  namespaceSelector:
    matchNames:
    - ${NAMESPACE}
  selector:
    matchLabels:
      app: ${EXPORTER_NAME}
---
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: ${DB_NAME}-rules
  namespace: ${NAMESPACE}
  labels:
    release: prometheus
spec:
  groups:
  - name: ${DB_NAME}.rules
    rules:
    - alert: ${DB_TYPE^}InstanceDown
      expr: up{job="${EXPORTER_NAME}"} == 0
      for: 5m
      labels:
        severity: critical
      annotations:
        summary: "${DB_TYPE^} instance is down"
        description: "${DB_TYPE^} instance has been down for more than 5 minutes."
    
    # Database-specific alerts
    - alert: ${DB_TYPE^}HighConnections
      expr: |
        ${DB_TYPE} == "mysql" && mysql_global_status_threads_connected > 80% * mysql_global_variables_max_connections ||
        ${DB_TYPE} == "postgres" && pg_stat_activity_count > 80% * pg_settings_max_connections ||
        ${DB_TYPE} == "mongodb" && mongodb_connections{state="current"} > 80% * mongodb_connections{state="available"}
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "High number of database connections"
        description: "More than 80% of available connections are in use."
    
    - alert: ${DB_TYPE^}HighCPUUsage
      expr: rate(process_cpu_seconds_total{job="${EXPORTER_NAME}"}[5m]) * 100 > 80
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "High CPU usage"
        description: "Database is using more than 80% CPU for 5 minutes."
    
    - alert: ${DB_TYPE^}HighMemoryUsage
      expr: |
        process_resident_memory_bytes{job="${EXPORTER_NAME}"} / container_memory_working_set_bytes{container="${DB_NAME}"} * 100 > 80
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "High memory usage"
        description: "Database is using more than 80% of allocated memory."
    
    - alert: ${DB_TYPE^}SlowQueries
      expr: |
        ${DB_TYPE} == "mysql" && rate(mysql_global_status_slow_queries[5m]) > 0 ||
        ${DB_TYPE} == "postgres" && rate(pg_stat_database_xact_commit{datname="${DB_NAME}"}[5m]) < 10 ||
        ${DB_TYPE} == "mongodb" && rate(mongodb_op_latencies_latency_total[5m]) > 100
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "Slow queries detected"
        description: "Database is experiencing slow query performance."
EOF
}

# Main deployment function
main() {
    echo "Starting database deployment..."

    echo "Configuring database..."
    configure_database
    echo "Database configuration completed."

    echo "Creating storage class..."
    create_storage_class
    echo "Storage class created."

    echo "Initializing host directory..."
    initialize_host_directory
    echo "Host directory initialized."

    echo "Creating namespace resources..."
    create_namespace_resources
    echo "Namespace resources created."

    echo "Creating persistent volume..."
    create_persistent_volume
    echo "Persistent volume created."

    echo "Creating persistent volume claim..."
    create_persistent_volume_claim
    echo "Persistent volume claim created."

    echo "Creating statefulset..."
    create_statefulset
    echo "Statefulset created."

    echo "Creating service..."
    create_service
    echo "Service created."

    echo "Creating ingress..."
    create_ingress
    echo "Ingress created."

    echo "Setting up monitoring..."
    create_monitoring_config
    echo "Monitoring setup completed."

    echo "✅ Database deployment completed!"
    echo "Access Info:"
    echo "- Internal: ${DB_NAME}.${NAMESPACE}.svc.cluster.local:${DB_PORT}"
    if [ ! -z "${DOMAIN_NAME}" ]; then
        echo "- External: ${DOMAIN_NAME}"
    fi
    echo "- NodePort: ${PORT}"
    echo ""
    echo "Monitoring Info:"
    echo "- Metrics endpoint: http://${DB_NAME}-${DB_TYPE}-exporter.${NAMESPACE}.svc.cluster.local:${METRICS_PORT}/metrics"
    echo "- ServiceMonitor: ${DB_NAME}-monitor"
    echo "- Grafana Dashboard IDs:"
    case ${DB_TYPE} in
        "mysql")
            echo "  * MySQL Overview: 7362"
            echo "  * MySQL Performance: 6239"
            ;;
        "postgres")
            echo "  * PostgreSQL Overview: 9628"
            echo "  * PostgreSQL Performance: 9628"
            ;;
        "mongodb")
            echo "  * MongoDB Overview: 2583"
            echo "  * MongoDB Performance: 7353"
            ;;
    esac
}

# Execute main function
main