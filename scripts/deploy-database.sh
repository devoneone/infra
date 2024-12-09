#!/bin/bash

# Input variables
DB_NAME=$1
DB_IMAGE=$2
NAMESPACE=${3:-default}
DB_PASSWORD=$4
DOMAIN_NAME=$5
EMAIL=$6
STORAGE_SIZE=${7:-1Gi}

# Exit on error
set -e

# Create namespace if not exists
kubectl create namespace ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

# Create secret for database password
kubectl create secret generic ${DB_NAME}-secret \
  --from-literal=password=${DB_PASSWORD} \
  --namespace=${NAMESPACE} \
  --dry-run=client -o yaml | kubectl apply -f -

# Create PersistentVolumeClaim
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

# Deploy database
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
        - name: ${DB_TYPE == "postgres" ? "POSTGRES_PASSWORD" : "MONGO_INITDB_ROOT_PASSWORD"}
          valueFrom:
            secretKeyRef:
              name: ${DB_NAME}-secret
              key: password
        ports:
        - containerPort: ${DB_TYPE == "postgres" ? 5432 : 27017}
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

# Create Ingress
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
              number: ${DB_TYPE == "postgres" ? 5432 : 27017}
EOF
