#!/bin/bash

# Script to scale deployments, delete ArgoCD app, and delete all services in a given namespace (no confirmation)

# Check if namespace and replica count are provided as arguments
if [ -z "$1" ] || [ -z "$2" ]; then
  echo "Usage: $0 <namespace> <replica_count>"
  exit 1
fi

NAMESPACE=$1
REPLICA_COUNT=$2

# Check and delete ArgoCD app if it exists
if argocd app get $NAMESPACE-argocd >/dev/null 2>&1; then
  echo "Deleting ArgoCD app: $NAMESPACE-argocd..."
  argocd app delete $NAMESPACE-argocd --yes
else
  echo "ArgoCD app $NAMESPACE-argocd does not exist. Skipping..."
fi

# Scale all deployments to the specified replica count
echo "Scaling all deployments in namespace: $NAMESPACE to replicas: $REPLICA_COUNT..."
kubectl scale --replicas=$REPLICA_COUNT deployment --all -n $NAMESPACE 

# Verify scaling
echo "Listing deployments in namespace: $NAMESPACE..."
kubectl get deployments -n $NAMESPACE


# Verify deletion
echo "Listing remaining services in namespace: $NAMESPACE..."
kubectl get services -n $NAMESPACE