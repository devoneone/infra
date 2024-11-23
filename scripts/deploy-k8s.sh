#!/bin/bash

# Input variables
APP_NAME=$1
IMAGE=$2
NAMESPACE=${3:-default}  # Optional, defaults to 'default'
FILE_Path=$4

kubectl create ns ${NAMESPACE}
# Check if required variables are provided
if [ -z "$APP_NAME" ] || [ -z "$IMAGE" ]; then
  echo "Usage: $0 <APP_NAME> <IMAGE> [NAMESPACE]"
  exit 1
fi
mkdir -p /root/cloudinator/${FILE_Path}
cd /root/cloudinator/${FILE_Path}
# Create a Kubernetes deployment manifest
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
        - containerPort: 80
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
      targetPort: 80 # Port the application listens on inside the pod

EOF

# Apply the manifest
kubectl apply -f ${APP_NAME}-deployment.yaml
