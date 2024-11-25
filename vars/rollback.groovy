def call() {
    def previousBuild = currentBuild.previousSuccessfulBuild
    if (previousBuild) {
        def previousImageTag = previousBuild.getEnvironment().get('DOCKER_IMAGE_TAG')
        echo "Rolling back to previous successful build: ${previousImageTag}"
        
        // Update the Kubernetes deployment with the previous image
        sh """
        kubectl set image deployment/${env.APP_NAME} ${env.APP_NAME}=${env.DOCKER_IMAGE_NAME}:${previousImageTag} -n ${env.NAMESPACE}
        """
        
        // Wait for the rollout to complete
        sh "kubectl rollout status deployment/${env.APP_NAME} -n ${env.NAMESPACE}"
    } else {
        error "No previous successful build found for rollback"
    }
}