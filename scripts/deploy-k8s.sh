#!/bin/bash

# Input variables
APP_NAME=$1
IMAGE=$2
NAMESPACE=${3:-default}
FILE_Path=$4
DOMAIN_NAME=$5
EMAIL=$6
PORT=$7

# Check if required variables are provided
if [ -z "$APP_NAME" ] || [ -z "$IMAGE" ] || [ -z "$DOMAIN_NAME" ] || [ -z "$EMAIL" ] || [ -z "$PORT" ]; then
  echo "Usage: $0 <APP_NAME> <IMAGE> [NAMESPACE] <FILE_Path> <DOMAIN_NAME> <EMAIL> <PORT>"
  exit 1
fi

# Create namespace if it doesn't exist
kubectl create ns ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

# Install cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.8.0/cert-manager.yaml

# Wait for cert-manager to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=cert-manager -n cert-manager --timeout=120s

# Create ClusterIssuer for Let's Encrypt
cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: ${EMAIL}
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx
EOF

# Prepare directory for manifest files
mkdir -p /root/cloudinator/${FILE_Path}
cd /root/cloudinator/${FILE_Path}

# Create a Kubernetes deployment and service manifest
cat <<EOF > ${APP_NAME}-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${APP_NAME}
  namespace: ${NAMESPACE}
spec:
  replicas: 2
  selector:
    matchLabels:
      app: ${APP_NAME}
  template:
    metadata:
      labels:
        app: ${APP_NAME}
    spec:
      containers:
      - name: ${APP_NAME}
        image: ${IMAGE}
        ports:
        - containerPort: ${PORT}
---
apiVersion: v1
kind: Service
metadata:
  name: ${APP_NAME}
  namespace: ${NAMESPACE}
spec:
  type: NodePort
  selector:
    app: ${APP_NAME}
  ports:
    - protocol: TCP
      port: 80
      targetPort: ${PORT}
EOF

# Apply deployment and service
kubectl apply -f ${APP_NAME}-deployment.yaml

# Create an Ingress manifest with TLS
cat <<EOF > ${APP_NAME}-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ${APP_NAME}-ingress
  namespace: ${NAMESPACE}
  annotations:
    kubernetes.io/ingress.class: nginx
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
spec:
  tls:
  - hosts:
    - ${DOMAIN_NAME}
    secretName: ${APP_NAME}-tls
  rules:
  - host: ${DOMAIN_NAME}
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: ${APP_NAME}
            port:
              number: 80
EOF

# Apply Ingress
kubectl apply -f ${APP_NAME}-ingress.yaml

# Output success message
echo "Deployment, Service, and Ingress for ${APP_NAME} created successfully in namespace ${NAMESPACE} with HTTPS enabled."

