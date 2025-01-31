#!/bin/bash

# Script to delete all services in a given namespace with confirmation

# Check if namespace is provided as an argument
if [ -z "$1" ]; then
  echo "Usage: $0 <namespace>"
  exit 1
fi

NAMESPACE=$1

# Confirmation prompt
read -p "Are you sure you want to delete all services in namespace: $NAMESPACE? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Operation cancelled."
  exit 1
fi

# DELETE ALL SERVICES
echo "Deleting all services in namespace: $NAMESPACE..."
kubectl delete services --all -n $NAMESPACE

# Verify deletion
echo "Listing remaining services in namespace: $NAMESPACE..."
kubectl get services -n $NAMESPACE
