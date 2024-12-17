#!/bin/bash

# Script to delete all Kubernetes services in a given namespace (no confirmation)

# Check if namespace is provided as an argument
if [ -z "$1" ]; then
  echo "Usage: $0 <namespace>"
  exit 1
fi

NAMESPACE=$1

# Delete all services without confirmation
echo "Deleting all services in namespace: $NAMESPACE..."
kubectl delete namespace $NAMESPACE --ignore-not-found

# Verify deletion
echo "Listing remaining services in namespace: $NAMESPACE..."
kubectl get services -n $NAMESPACE
