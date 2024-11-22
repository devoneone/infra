def call(String projectPath) {
    def projectType = org.cloudinator.ProjectTypeDetector.detectProjectType(projectPath)

    if (projectType) {
        echo "Detected project type: ${projectType}"

        if (!dockerfileExists(projectPath)) {
            def packageManager = org.cloudinator.ProjectTypeDetector.detectPackageManager(projectPath)
            org.cloudinator.ProjectTypeDetector.writeDockerfile(projectType, projectPath, packageManager)
        } else {
            echo "Dockerfile already exists at ${projectPath}/Dockerfile, skipping generation."
        }

        return projectType
    } else {
        error "Unable to detect the project type for ${projectPath}."
    }
}

def dockerfileExists(String projectPath) {
    return fileExists("${projectPath}/Dockerfile")
}
