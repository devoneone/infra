#!/bin/bash

APP_NAME=$1
IMAGE=$2
NAMESPACE=$3
FILE_Path=$4

mkdir -p /root/cloudinator/${FILE_Path}
cd /root/cloudinator/${FILE_Path}

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
      port: 80
      targetPort: 80
EOF

kubectl apply -f ${APP_NAME}-deployment.yaml

