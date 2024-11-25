def call(String imageName, String imageTag) {
    echo "Building Docker image ${imageName}:${imageTag}"
    sh "docker build -t ${imageName}:${imageTag} ."
}