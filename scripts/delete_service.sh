#!/bin/bash

# Script to delete all services in a given namespace with confirmation

# Check if namespace is provided as an argument
if [ -z "$1" ]; then
  echo "Usage: $0 <namespace>"
  exit 1
fi

NAMESPACE=$1



# DELETE ALL SERVICES
echo "Deleting all services in namespace: $NAMESPACE..."
kubectl delete services --all -n $NAMESPACE

# Verify deletion
echo "Listing remaining services in namespace: $NAMESPACE..."
kubectl get services -n $NAMESPACE
