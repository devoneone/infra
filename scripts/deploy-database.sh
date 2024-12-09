#!/bin/bash

# Input variables
DB_NAME=$1
DB_IMAGE=$2
NAMESPACE=${3:-default}
DB_PASSWORD=$4
DB_USERNAME=${5:-defaultUser}  # Added default username
DOMAIN_NAME=$6
EMAIL=$7
STORAGE_SIZE=${8:-1Gi}

# Exit on error
set -e

# Determine environment variable names and port based on database type
if [[ ${DB_IMAGE} == *"postgres"* ]]; then
  ENV_USERNAME_VAR="POSTGRES_USER"
  ENV_PASSWORD_VAR="POSTGRES_PASSWORD"
  DB_PORT=5432
elif [[ ${DB_IMAGE} == *"mongo"* ]]; then
  ENV_USERNAME_VAR="MONGO_INITDB_ROOT_USERNAME"
  ENV_PASSWORD_VAR="MONGO_INITDB_ROOT_PASSWORD"
  DB_PORT=27017
else
  echo "Unsupported database type. Use postgres or mongo."
  exit 1
fi

# Create namespace if it doesn't exist
kubectl create namespace ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

# Create a secret for the database credentials
kubectl create secret generic ${DB_NAME}-secret \
  --from-literal=username=${DB_USERNAME} \
  --from-literal=password=${DB_PASSWORD} \
  --namespace=${NAMESPACE} \
  --dry-run=client -o yaml | kubectl apply -f -

# Create a PersistentVolumeClaim for database storage
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
      storage: ${STORAGE_SIZE}
EOF

# Deploy the database
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${DB_NAME}
  namespace: ${NAMESPACE}
spec:
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
        env:
        - name: ${ENV_USERNAME_VAR}
          valueFrom:
            secretKeyRef:
              name: ${DB_NAME}-secret
              key: username
        - name: ${ENV_PASSWORD_VAR}
          valueFrom:
            secretKeyRef:
              name: ${DB_NAME}-secret
              key: password
        ports:
        - containerPort: ${DB_PORT}
        volumeMounts:
        - name: ${DB_NAME}-storage
          mountPath: /data/db
        resources:
          requests:
            memory: "256Mi"
            cpu: "500m"
          limits:
            memory: "512Mi"
            cpu: "1000m"
      volumes:
      - name: ${DB_NAME}-storage
        persistentVolumeClaim:
          claimName: ${DB_NAME}-pvc
EOF

# Create an Ingress resource for the database
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ${DB_NAME}-ingress
  namespace: ${NAMESPACE}
  annotations:
    kubernetes.io/ingress.class: nginx
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
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

echo "Database ${DB_NAME} deployed successfully in namespace ${NAMESPACE}."
