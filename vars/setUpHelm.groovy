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
        if (!fileExists(inventoryFile)) {
            error "Inventory file not found: ${inventoryFile}"
        }
        if (!fileExists(playbookFile)) {
            error "Playbook file not found: ${playbookFile}"
        }
        if (!appName?.trim()) {
            error "App name cannot be empty"
        }
        // Add more validations as needed

        // Execute deployment
        sh """
        ansible-playbook -i ${inventoryFile} ${playbookFile} \
        -e "CHART_NAME=${appName}" \
        -e "IMAGE=${image}" \
        -e "TAG=${tag}" \
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
