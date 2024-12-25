#!/bin/bash

# Input variables
DB_NAME=$1
DB_TYPE=$2
DB_VERSION=$3
NAMESPACE=${4:-default}
DB_PASSWORD=$5
DB_USERNAME=${6:-defaultUser}
DOMAIN_NAME=$7
STORAGE_SIZE=${8:-1Gi}


# Function to set database-specific configurations
configure_database() {
    case ${DB_TYPE} in
        "postgres")
            DB_IMAGE="postgres:${DB_VERSION}"
            ENV_USERNAME_VAR="POSTGRES_USER"
            ENV_PASSWORD_VAR="POSTGRES_PASSWORD"
            ENV_DB_VAR="POSTGRES_DB"
            DB_PORT=5432
            VOLUME_MOUNT_PATH="/var/lib/postgresql/data"
            HEALTHCHECK_CMD='["CMD-SHELL", "pg_isready -U $POSTGRES_USER"]'
            RESOURCE_REQUEST_CPU="100m"
            RESOURCE_REQUEST_MEM="128Mi"
            RESOURCE_LIMIT_CPU="200m"
            RESOURCE_LIMIT_MEM="256Mi"
            ;;
        "mysql")
            DB_IMAGE="mysql:${DB_VERSION}"
            ENV_USERNAME_VAR="MYSQL_USER"
            ENV_PASSWORD_VAR="MYSQL_ROOT_PASSWORD"
            ENV_DB_VAR="MYSQL_DATABASE"
            DB_PORT=3306
            VOLUME_MOUNT_PATH="/var/lib/mysql"
            HEALTHCHECK_CMD='["CMD", "mysqladmin", "ping", "-h", "localhost"]'
            RESOURCE_REQUEST_CPU="200m"
            RESOURCE_REQUEST_MEM="256Mi"
            RESOURCE_LIMIT_CPU="400m"
            RESOURCE_LIMIT_MEM="512Mi"
            ;;
        "mongodb")
            DB_IMAGE="mongo:${DB_VERSION}"
            ENV_USERNAME_VAR="MONGO_INITDB_ROOT_USERNAME"
            ENV_PASSWORD_VAR="MONGO_INITDB_ROOT_PASSWORD"
            ENV_DB_VAR="MONGO_INITDB_DATABASE"
            DB_PORT=27017
            VOLUME_MOUNT_PATH="/data/db"
            HEALTHCHECK_CMD='["CMD", "mongosh", "--eval", "db.adminCommand(\"ping\")"]'
            RESOURCE_REQUEST_CPU="200m"
            RESOURCE_REQUEST_MEM="256Mi"
            RESOURCE_LIMIT_CPU="400m"
            RESOURCE_LIMIT_MEM="512Mi"
            ;;
        *)
            echo "Unsupported database type. Use postgres, mysql, or mongodb."
            exit 1
            ;;
    esac
}

# Create StorageClass
create_storage_class() {
    cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ${DB_NAME}-storage
  labels:
    app.kubernetes.io/name: ${DB_NAME}
    app.kubernetes.io/component: database
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
reclaimPolicy: Retain
EOF
}

# Create PV with smaller default size
create_persistent_volume() {
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolume
metadata:
  name: ${DB_NAME}-pv
  namespace: ${NAMESPACE}
  labels:
    app.kubernetes.io/name: ${DB_NAME}
    app.kubernetes.io/component: database
spec:
  capacity:
    storage: ${STORAGE_SIZE}
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: ${DB_NAME}-storage
  hostPath:
    path: /data/${NAMESPACE}/${DB_NAME}
    type: DirectoryOrCreate
EOF
}

# Create namespace and optimized resources
create_namespace_resources() {
    # Create namespace
    kubectl create namespace ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

    # Create ResourceQuota with optimized values
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ResourceQuota
metadata:
  name: ${DB_NAME}-quota
  namespace: ${NAMESPACE}
spec:
  hard:
    requests.cpu: "500m"
    requests.memory: 512Mi
    limits.cpu: "1"
    limits.memory: 1Gi
    persistentvolumeclaims: "3"
EOF

    # Create secret
    kubectl create secret generic ${DB_NAME}-secret \
        --from-literal=${ENV_USERNAME_VAR}=${DB_USERNAME} \
        --from-literal=${ENV_PASSWORD_VAR}=${DB_PASSWORD} \
        --from-literal=${ENV_DB_VAR}=${DB_NAME} \
        --namespace=${NAMESPACE} \
        --dry-run=client -o yaml | kubectl apply -f -

    # Create PVC
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${DB_NAME}-pvc
  namespace: ${NAMESPACE}
  labels:
    app.kubernetes.io/name: ${DB_NAME}
    app.kubernetes.io/component: database
spec:
  storageClassName: ${DB_NAME}-storage
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: ${STORAGE_SIZE}
EOF
}

# Deploy database StatefulSet with optimized resources
deploy_database() {
    cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: ${DB_NAME}
  namespace: ${NAMESPACE}
  labels:
    app.kubernetes.io/name: ${DB_NAME}
    app.kubernetes.io/component: database
    app.kubernetes.io/instance: ${DB_NAME}
    app.kubernetes.io/version: "${DB_VERSION}"
spec:
  serviceName: ${DB_NAME}
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: ${DB_NAME}
  template:
    metadata:
      labels:
        app.kubernetes.io/name: ${DB_NAME}
        app.kubernetes.io/component: database
        app.kubernetes.io/instance: ${DB_NAME}
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 999
        fsGroup: 999
        allowPrivilegeEscalation: false
      containers:
      - name: ${DB_NAME}
        image: ${DB_IMAGE}
        imagePullPolicy: IfNotPresent
        securityContext:
          allowPrivilegeEscalation: false
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
            memory: ${RESOURCE_REQUEST_MEM}
            cpu: ${RESOURCE_REQUEST_CPU}
          limits:
            memory: ${RESOURCE_LIMIT_MEM}
            cpu: ${RESOURCE_LIMIT_CPU}
        startupProbe:
          exec:
            command: ${HEALTHCHECK_CMD}
          failureThreshold: 30
          periodSeconds: 10
        readinessProbe:
          exec:
            command: ${HEALTHCHECK_CMD}
          initialDelaySeconds: 20
          periodSeconds: 10
        livenessProbe:
          exec:
            command: ${HEALTHCHECK_CMD}
          initialDelaySeconds: 30
          periodSeconds: 10
      # Add anti-affinity to spread pods across nodes
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            podAffinityTerm:
              labelSelector:
                matchExpressions:
                - key: app.kubernetes.io/name
                  operator: In
                  values:
                  - ${DB_NAME}
              topologyKey: kubernetes.io/hostname
  volumeClaimTemplates:
  - metadata:
      name: data
      labels:
        app.kubernetes.io/name: ${DB_NAME}
        app.kubernetes.io/component: database
    spec:
      accessModes: [ "ReadWriteOnce" ]
      storageClassName: ${DB_NAME}-storage
      resources:
        requests:
          storage: ${STORAGE_SIZE}
EOF
}

# Create service with optimized timeout values
create_service() {
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: ${DB_NAME}
  namespace: ${NAMESPACE}
  labels:
    app.kubernetes.io/name: ${DB_NAME}
    app.kubernetes.io/component: database
spec:
  type: ClusterIP
  ports:
    - port: ${DB_PORT}
      targetPort: db-port
      protocol: TCP
      name: db-port
  selector:
    app.kubernetes.io/name: ${DB_NAME}
EOF
}

# Create network policy with specific rules
create_network_policy() {
    cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: ${DB_NAME}-network-policy
  namespace: ${NAMESPACE}
  labels:
    app.kubernetes.io/name: ${DB_NAME}
    app.kubernetes.io/component: database
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: ${DB_NAME}
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          access: ${DB_NAME}
    - podSelector:
        matchLabels:
          access: ${DB_NAME}
    ports:
    - protocol: TCP
      port: ${DB_PORT}
  policyTypes:
  - Ingress
EOF
}

# Create Ingress with optimized configurations
create_ingress() {
    cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ${DB_NAME}-ingress
  namespace: ${NAMESPACE}
  labels:
    app.kubernetes.io/name: ${DB_NAME}
    app.kubernetes.io/component: database
  annotations:
    kubernetes.io/ingress.class: nginx
    cert-manager.io/cluster-issuer: "letsencrypt-dns"
spec:
  tls:
  - hosts:
    - ${DOMAIN_NAME}
    secretName: ${DB_NAME}-tls
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
EOF
}

# Main execution
main() {
    configure_database
    create_storage_class
    create_persistent_volume
    create_namespace_resources
    deploy_database
    create_service
    create_network_policy
    create_ingress
    
    echo "✅ Database deployment completed successfully!"
    echo "📊 Database Details:"
    echo "  - Name: ${DB_NAME}"
    echo "  - Type: ${DB_TYPE}"
    echo "  - Version: ${DB_VERSION}"
    echo "  - Namespace: ${NAMESPACE}"
    echo "  - Domain: ${DOMAIN_NAME}"
    echo "  - Port: ${DB_PORT}"
    echo "  - CPU Request: ${RESOURCE_REQUEST_CPU}"
    echo "  - Memory Request: ${RESOURCE_REQUEST_MEM}"
    echo ""
    echo "🔌 Connection Information:"
    echo "  - Internal: ${DB_NAME}.${NAMESPACE}.svc.cluster.local:${DB_PORT}"
    echo "  - External: ${DOMAIN_NAME}"
    echo ""
    echo "⏳ Wait for the database to be ready:"
    echo "  kubectl get pods -n ${NAMESPACE} -l app.kubernetes.io/name=${DB_NAME} -w"
    echo ""
    echo "💡 Resource Usage Tips:"
    echo "  - Monitor resource usage with: kubectl top pods -n ${NAMESPACE}"
    echo "  - Check logs with: kubectl logs -n ${NAMESPACE} ${DB_NAME}-0"
    echo "  - View details with: kubectl describe pod -n ${NAMESPACE} ${DB_NAME}-0"
}

# Execute main function
main