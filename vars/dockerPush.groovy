def call(String imageName, String imageTag, String credentialsId) {
    withCredentials([usernamePassword(credentialsId: credentialsId, passwordVariable: 'DOCKER_PASSWORD', usernameVariable: 'DOCKER_USERNAME')]) {
        sh "echo $DOCKER_PASSWORD | docker login -u $DOCKER_USERNAME --password-stdin"
        sh "docker push ${imageName}:${imageTag}"
        sh "docker logout"
    }
}   