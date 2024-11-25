def call(Map args) {
    sh """
    helm upgrade --install ${args.appName} ${args.helmChartPath} \
        --namespace ${args.namespace} --create-namespace \
        --set image.repository=${args.image} \
        --set ingress.host=${args.domainName} \
        --set ingress.email=${args.email} \
        --set service.port=${args.port}
    """
}
