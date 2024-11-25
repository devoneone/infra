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

# Create Helm chart and update values
ansible-playbook -i /root/cloudinator/inventory/inventory.ini /root/cloudinator/playbooks/create-helm-chart.yml \
  -e "APP_NAME=${APP_NAME}" \
  -e "IMAGE=${IMAGE}" \
  -e "NAMESPACE=${NAMESPACE}" \
  -e "FILE_Path=${FILE_Path}" \
  -e "DOMAIN_NAME=${DOMAIN_NAME}" \
  -e "EMAIL=${EMAIL}" \
  -e "PORT=${PORT}"

# Install/Upgrade Helm chart
helm upgrade --install ${APP_NAME} /root/cloudinator/${FILE_Path}/${APP_NAME}-chart \
  --namespace ${NAMESPACE} \
  --create-namespace \
  --set ingress.annotations."cert-manager\.io/cluster-issuer"=letsencrypt-prod

# Wait for deployment to be ready
kubectl rollout status deployment/${APP_NAME} -n ${NAMESPACE}

# Output success message
echo "Helm chart for ${APP_NAME} installed/upgraded successfully in namespace ${NAMESPACE} with HTTPS enabled."

