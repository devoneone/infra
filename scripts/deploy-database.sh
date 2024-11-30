#!/bin/bash

# Input variables
DB_NAME=$1
DB_IMAGE=$2
NAMESPACE=${3:-default}
DB_PASSWORD=$4
DOMAIN_NAME=$5
EMAIL=$6

# Check if required variables are provided
if [ -z "$DB_NAME" ] || [ -z "$DB_IMAGE" ] || [ -z "$DB_PASSWORD" ] || [ -z "$DOMAIN_NAME" ] || [ -z "$EMAIL" ]; then
  echo "Usage: $0 <DB_NAME> <DB_IMAGE> [NAMESPACE] <DB_PASSWORD> <DOMAIN_NAME> <EMAIL>"
  exit 1
fi

# Determine database type based on image name
if [[ $DB_IMAGE == *"mongo"* ]]; then
  DB_TYPE="mongodb"
  ENV_VAR_NAME="MONGO_INITDB_ROOT_PASSWORD"
  CONTAINER_PORT=27017
elif [[ $DB_IMAGE == *"postgres"* ]]; then
  DB_TYPE="postgres"
  ENV_VAR_NAME="POSTGRES_PASSWORD"
  CONTAINER_PORT=5432
else
  echo "Unsupported database image: $DB_IMAGE"
  exit 1
fi

# Create namespace if it doesn't exist
kubectl create namespace ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

# Create a secret for the database password
kubectl create secret generic ${DB_NAME}-secret \
  --from-literal=password=${DB_PASSWORD} \
  --namespace=${NAMESPACE} \
  --dry-run=client -o yaml | kubectl apply -f -

# Create a PersistentVolumeClaim for the database
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
      storage: 1Gi
EOF

# Create the database deployment
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
        - name: ${ENV_VAR_NAME}
          valueFrom:
            secretKeyRef:
              name: ${DB_NAME}-secret
              key: password
        ports:
        - containerPort: ${CONTAINER_PORT}
        volumeMounts:
        - name: ${DB_NAME}-storage
          mountPath: /data/db
      volumes:
      - name: ${DB_NAME}-storage
        persistentVolumeClaim:
          claimName: ${DB_NAME}-pvc
---
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
      port: ${CONTAINER_PORT}
      targetPort: ${CONTAINER_PORT}
EOF

# Create an Ingress for the database (if needed)
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
              number: ${CONTAINER_PORT}
EOF

echo "Database ${DB_NAME} (${DB_TYPE}) deployed successfully in namespace ${NAMESPACE} with HTTPS enabled."

