
def call(String inventoryFile, String playbookFile, String appName, String image, 
         String namespace, String filePath, String domainName, String email, String gitRepoUrl) {
    
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
        
        def port = projectInfo.port ?: 80
        
        echo """
        Project Detection Results:
        -------------------------
        Type: ${projectInfo.type}
        Port: ${port}
        Path: ${tmpDir}
        """

        // Validate parameters
        validateParameters(inventoryFile, playbookFile, appName, image, namespace, filePath, domainName, email)

        // Execute deployment
        sh """
        ansible-playbook -i ${inventoryFile} ${playbookFile} \
        -e "APP_NAME=${appName}" \
        -e "IMAGE=${image}" \
        -e "NAMESPACE=${namespace}" \
        -e "FILE_Path=${filePath}" \
        -e "DOMAIN_NAME=${domainName}" \
        -e "EMAIL=${email}" \
        -e "PORT=${port}"
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
                      String image, String namespace, String filePath, 
                      String domainName, String email) {
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
        if (fileExists("${projectPath}/artisan")) {
        echo "Laravel project detected"
        return [type: 'laravel', port: 8000]
    }
    else if (fileExists("${projectPath}/package.json")) {
        def packageJson = readJSON file: "${projectPath}/package.json"
        echo "package.json contents: ${packageJson}"

        if (packageJson.dependencies?.next || packageJson.devDependencies?.next) {
            echo "Next.js project detected, setting port to 3000"
            return [type: 'nextjs', port: 3000]
        } else if (packageJson.dependencies?.react || packageJson.devDependencies?.react) {
            if (packageJson.dependencies?.vite || packageJson.devDependencies?.vite) {
                echo "React Vite project detected, setting port to 80"
                return [type: 'vite-react', port: 80]
            } else {
                echo "React project detected, setting port to 80"
                return [type: 'react', port: 80]
            }
        }else if (packageJson.dependencies?.nuxt || packageJson.devDependencies?.nuxt) {
            echo "Nuxt.js project detected, setting port to 3000"
            return [type: 'nuxtjs', port: 3000]
        }else if (packageJson.dependencies?.vue || packageJson.devDependencies?.vue) {
            echo "Vue.js project detected, setting port to 8080"
            return [type: 'vuejs', port: 80]
        } else if (packageJson.dependencies?.angular || packageJson.devDependencies?.angular) {
            echo "Angular project detected, setting port to 4200"
            return [type: 'angular', port: 4200]
        }  else if (packageJson.dependencies?.svelte || packageJson.devDependencies?.svelte) {
            echo "Svelte project detected, setting port to 5000"
            return [type: 'svelte', port: 5000]
        } else if (packageJson.dependencies?.express || packageJson.devDependencies?.express) {
            echo "Express project detected, setting port to 3000"
            return [type: 'express', port: 3000]
        } else if (packageJson.dependencies?.nestjs || packageJson.devDependencies?.nestjs) {
            echo "NestJS project detected, setting port to 3000"
            return [type: 'nestjs', port: 3000]
        }
    }else if (fileExists("${projectPath}/index.html")) {
        echo "HTML project detected"
        return [type: 'html', port: 80]
    } else if (fileExists("${projectPath}/index.php")) {
        echo "PHP project detected"
        return [type: 'php']
    } 

    //Detecting Backend Projects
    else if (fileExists("${projectPath}/pom.xml")) {
        echo "Spring Boot (Maven) project detected, setting port to 8080"
        return [type: 'springboot-maven', port: 8080]
    } else if (fileExists("${projectPath}/build.gradle") || fileExists("${projectPath}/build.gradle.kts")) {
        echo "Spring Boot (Gradle) project detected, setting port to 8080"
        return [type: 'springboot-gradle', port: 8080]
    } else if (fileExists("${projectPath}/pubspec.yaml")) {
        echo "Flutter project detected, setting port to 8080"
        return [type: 'flutter', port: 8080]
    }
        echo "No specific project type detected, using default configuration"
        return [type: 'unknown', port: 8080]
    } catch (Exception e) {
        echo "Error detecting project type: ${e.message}"
        return [type: 'unknown', port: 8080]
    }
}