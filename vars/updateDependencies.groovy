def call() {
    try {
        if (fileExists('package.json')) {
            echo "package.json found. Updating npm dependencies."
            
            // Attempt to update dependencies and resolve conflicts with legacy-peer-deps
            sh 'npm update --save'
            
            // Use --legacy-peer-deps to bypass dependency resolution conflicts
            sh 'npm install --legacy-peer-deps'
            
            // Optional: Add a fallback to force install if issues persist
            echo "If dependency issues persist, use --force to proceed."
        } else if (fileExists('pom.xml')) {
            echo "pom.xml found. Updating Maven dependencies."
            sh 'mvn versions:use-latest-versions -DgenerateBackupPoms=false'
            sh 'mvn clean install'
        } else if (fileExists('build.gradle') || fileExists('build.gradle.kts')) {
            echo "Gradle build file found. Updating Gradle dependencies."
            sh './gradlew dependencyUpdates'
            sh './gradlew build'
        } else {
            echo "No recognized dependency file found. Skipping dependency update."
        }
    } catch (Exception e) {
        echo "An error occurred while updating dependencies: ${e.getMessage()}"
        currentBuild.result = 'FAILURE'
        throw e
    }
}
