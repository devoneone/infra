#!/bin/bash

# Input variables
APP_NAME=$1
IMAGE=$2
NAMESPACE=${3:-default}  # Optional, defaults to 'default'
FILE_Path=$4
DOMAIN_NAME=$5  # New parameter for the domain name

# Check if required variables are provided
if [ -z "$APP_NAME" ] || [ -z "$IMAGE" ] || [ -z "$DOMAIN_NAME" ]; then
  echo "Usage: $0 <APP_NAME> <IMAGE> [NAMESPACE] <FILE_Path> <DOMAIN_NAME>"
  exit 1
fi

# Create namespace if it doesn't exist
kubectl create ns ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

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
        - containerPort: 3000
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
      port: 80       # Port the service exposes inside the cluster
      targetPort: 3000 # Port the application listens on inside the pod
EOF

# Apply deployment and service
kubectl apply -f ${APP_NAME}-deployment.yaml

# Create an Ingress manifest
cat <<EOF > ${APP_NAME}-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ${APP_NAME}-ingress
  namespace: ${NAMESPACE}
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
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
echo "Deployment, Service, and Ingress for ${APP_NAME} created successfully in namespace ${NAMESPACE}."
