def call() {
    def projectType = detectProjectType("${env.WORKSPACE}").type
    
    switch(projectType) {
        case 'nextjs':
        case 'react':
            sh 'npm test'
            break
        case 'springboot-maven':
            sh 'mvn test'
            break
        case 'springboot-gradle':
            sh './gradlew test'
            break
        case 'flutter':
            sh 'flutter test'
            break
        default:
            error "Unsupported project type for testing: ${projectType}"
    }
}