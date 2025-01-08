def call() {
    try {
        if (fileExists('package.json')) {
            echo "package.json found. Updating npm dependencies."

            // Attempt to update dependencies first
            try {
                echo "Running 'npm update'..."
                sh 'npm update --save'
            } catch (Exception updateError) {
                echo "npm update failed with ERESOLVE. Proceeding with --legacy-peer-deps..."
            }

            // Install dependencies with --legacy-peer-deps to bypass strict conflicts
            try {
                echo "Running 'npm install --legacy-peer-deps'..."
                sh 'npm install --legacy-peer-deps'
            } catch (Exception legacyError) {
                echo "npm install with --legacy-peer-deps failed. Attempting with --force..."

                // Fallback: Force install as a last resort
                echo "Running 'npm install --force'..."
                sh 'npm install --force'
            }
    //     } else if (fileExists('pom.xml')) {
    //     sh 'mvn versions:use-latest-versions'
    // } else if (fileExists('build.gradle') || fileExists('build.gradle.kts')) {
    //     sh 'gradle useLatestVersions'
    // } else {
    //     echo "No recognized dependency file found. Skipping dependency update."
    // }
    } catch (Exception e) {
        echo "An error occurred while updating dependencies: ${e.getMessage()}"
        currentBuild.result = 'FAILURE'
        throw e
    }
}
