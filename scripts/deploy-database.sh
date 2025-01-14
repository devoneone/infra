# Create Service
create_service() {
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: ${DB_NAME}
  namespace: ${NAMESPACE}
  labels:
    app: ${DB_NAME}
    type: database
spec:
  type: NodePort
  ports:
    - port: ${DB_PORT}
      targetPort: ${DB_PORT}
      protocol: TCP
      name: db-port
      nodePort: ${PORT}
  selector:
    app: ${DB_NAME}
    type: database
EOF
}

# Create Ingress
create_ingress() {
    if [ ! -z "${DOMAIN_NAME}" ]; then
        cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ${DB_NAME}-ingress
  namespace: ${NAMESPACE}
  annotations:
    kubernetes.io/ingress.class: nginx
    cert-manager.io/cluster-issuer: "letsencrypt-dns"
    nginx.ingress.kubernetes.io/backend-protocol: "TCP"
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
    nginx.ingress.kubernetes.io/ssl-passthrough: "true"
spec:
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
              number: ${DB_PORT}
  tls:
  - hosts:
    - ${DOMAIN_NAME}
    secretName: ${DB_NAME}-tls
EOF
    fi
}

# Main deployment function
main() {
    echo "🚀 Starting database deployment..."

    # Create namespace first
    echo "🔑 Creating namespace..."
    create_namespace_resources

    # Validate deployment
    validate_unique_deployment

    # Get node name for PV node affinity
    NODE_NAME=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
    echo "Debug - Selected Node: ${NODE_NAME}"

    echo "⚙️ Configuring database..."
    configure_database

    echo "📂 Creating StorageClass..."
    create_storage_class

    echo "🔒 Creating NetworkPolicy..."
    create_network_policy

    echo "📂 Initializing storage..."
    initialize_host_directory

    echo "💾 Creating PV..."
    create_persistent_volume

    echo "📝 Creating PVC..."
    create_persistent_volume_claim

    echo "⏳ Waiting for PVC to bind..."
    kubectl wait --for=condition=Bound pvc/${DB_NAME}-pvc -n ${NAMESPACE} --timeout=60s

    echo "🚀 Creating StatefulSet..."
    create_statefulset

    echo "🔌 Creating Service..."
    create_service

    if [ ! -z "${DOMAIN_NAME}" ]; then
        echo "🌐 Creating Ingress..."
        create_ingress
    fi

    echo "✅ Database deployment completed successfully!"
    echo ""
    echo "📊 Database Details:"
    echo "  - Name: ${DB_NAME}"
    echo "  - Type: ${DB_TYPE}"
    echo "  - Version: ${DB_VERSION}"
    echo "  - Namespace: ${NAMESPACE}"
    echo "  - Port: ${DB_PORT}"
    echo ""
    echo "🔌 Connection Information:"
    echo "  - Internal: ${DB_NAME}.${NAMESPACE}.svc.cluster.local:${DB_PORT}"
    if [ ! -z "${DOMAIN_NAME}" ]; then
        echo "  - External: ${DB_NAME}-${NAMESPACE}.${DOMAIN_NAME}"
    fi
    echo "  - NodePort: ${PORT}"
    echo "⏳ Wait for the database to be ready:"
    echo "  kubectl get pods -n ${NAMESPACE} -l app=${DB_NAME} -w"
    echo "  kubectl logs -f -n ${NAMESPACE} -l app=${DB_NAME}"
}

# Execute main function
main
