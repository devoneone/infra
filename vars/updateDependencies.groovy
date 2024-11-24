def call() {
    if (fileExists('package.json')) {
        sh 'npm update --save'
        sh 'npm install'
    } else if (fileExists('pom.xml')) {
        sh 'mvn versions:use-latest-versions'
    } else if (fileExists('build.gradle') || fileExists('build.gradle.kts')) {
        sh 'gradle useLatestVersions'
    } else {
        echo "No recognized dependency file found. Skipping dependency update."
    }
}

