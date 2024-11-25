def call(String imageName, String imageTag) {
    sh "docker push ${imageName}:${imageTag}"
    sh "docker logout"
}   