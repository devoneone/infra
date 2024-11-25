def call(String inventoryFile, String playbookFile, String appName, String image, 
         String namespace, String tag, String domainName, String gitRepoUrl) {
    
    def tmpDir = "tmp-${appName}-${UUID.randomUUID().toString()}"
    
    try {
        // Clone with credentials if needed
        dir(tmpDir) {
            git(
                url: gitRepoUrl,
                branch: 'main',  // or specify branch as parameter
                credentialsId: 'git-credentials'  // specify your credentials ID
            )
        }
        
        // Detect project type and get port
        def projectInfo = detectProjectType(tmpDir)
        if (!projectInfo) {
            error "Failed to detect project type for repository: ${gitRepoUrl}"
        }
        
        def port = projectInfo.port ?: 8080
        
        echo """
        Project Detection Results:
        -------------------------
        Type: ${projectInfo.type}
        Port: ${port}
        Path: ${tmpDir}
        """

        // Validate parameters
        validateParameters(inventoryFile, playbookFile, appName, image,  ,namespace , domainName)

        // Execute deployment
        sh """
        ansible-playbook -i ${inventoryFile} ${playbookFile} \
        -e "CHART_NAME=${appName}" \
        -e "IMAGE=${image}" \
        -e "TAG=${namespace}" \
        -e "PORT=${port}" \
        -e "NAMESPACE=${namespace}" \
        -e "HOST=${domainName}" 
        """
        
    } catch (Exception e) {
        echo "Deployment failed: ${e.message}"
        throw e
    } finally {
        // Cleanup
        sh "rm -rf ${tmpDir}"
    }
}

def validateParameters(String inventoryFile, String playbookFile, String appName, 
                      String image, String tag, String namespace, 
                      String domainName) {
    if (!fileExists(inventoryFile)) {
        error "Inventory file not found: ${inventoryFile}"
    }
    if (!fileExists(playbookFile)) {
        error "Playbook file not found: ${playbookFile}"
    }
    if (!appName?.trim()) {
        error "App name cannot be empty"
    }
    // Add more validation as needed
}

def detectProjectType(String projectPath = '.') {
    echo "Detecting project type for path: ${projectPath}"
    
    try {
        if (fileExists("${projectPath}/package.json")) {
            def packageJson = readJSON file: "${projectPath}/package.json"
            
            if (packageJson.dependencies?.next || packageJson.devDependencies?.next) {
                return [type: 'nextjs', port: 3000]
            } else if (packageJson.dependencies?.react || packageJson.devDependencies?.react) {
                return [type: 'react', port: 3000]
            }
        } else if (fileExists("${projectPath}/pom.xml")) {
            return [type: 'springboot-maven', port: 8080]
        } else if (fileExists("${projectPath}/build.gradle") || fileExists("${projectPath}/build.gradle.kts")) {
            return [type: 'springboot-gradle', port: 8080]
        } else if (fileExists("${projectPath}/pubspec.yaml")) {
            return [type: 'flutter', port: 8080]
        }
        
        echo "No specific project type detected, using default configuration"
        return [type: 'unknown', port: 8080]
    } catch (Exception e) {
        echo "Error detecting project type: ${e.message}"
        return [type: 'unknown', port: 8080]
    }
}