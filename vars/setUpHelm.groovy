def call(String inventoryFile, String playbookFile, String serviceName, String image, 
         String namespace, String tag, String domainName, String gitRepoUrl) {
    
    def tmpDir = "tmp-${serviceName}-${UUID.randomUUID().toString()}"
    
    try {
        dir(tmpDir) {
            git(url: gitRepoUrl, branch: 'main', credentialsId: 'git-credentials')
        }
        
        def projectInfo = detectProjectType(tmpDir)
        if (!projectInfo) {
            error "Failed to detect project type for repository: ${gitRepoUrl}"
        }
        
        def port = projectInfo.port ?: 80
        
        echo """
        Project Detection Results for ${serviceName}:
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
        if (!serviceName?.trim()) {
            error "Service name cannot be empty"
        }

        // Execute deployment
        sh """
        ansible-playbook -i ${inventoryFile} ${playbookFile} \
        -e "CHART_NAME=${serviceName}" \
        -e "IMAGE=${image}" \
        -e "TAG=${tag}" \
        -e "PORT=${port}" \
        -e "NAMESPACE=${namespace}" \
        -e "HOST=${domainName}" 
        """
        
    } catch (Exception e) {
        echo "Helm setup failed for ${serviceName}: ${e.message}"
        throw e
    } finally {
        sh "rm -rf ${tmpDir}"
    }
}

def validateParameters(String inventoryFile, String playbookFile, String serviceName, 
                       String image, String namespace, String filePath, 
                       String domainName, String email) {
    if (!fileExists(inventoryFile)) {
        error "Inventory file not found: ${inventoryFile}"
    }
    if (!fileExists(playbookFile)) {
        error "Playbook file not found: ${playbookFile}"
    }
    if (!serviceName?.trim()) {
        error "Service name cannot be empty"
    }
    // Add more validation as needed
}

def detectProjectType(String projectPath = '.') {
    echo "Detecting project type for path: ${projectPath}"

    try {
        if (fileExists("${projectPath}/artisan")) {
            echo "Laravel project detected"
            return [type: 'laravel', port: 8000]
        } else if (fileExists("${projectPath}/package.json")) {
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
                    echo "React project detected, setting port to 3000"
                    return [type: 'react', port: 3000]
                }
            } else if (packageJson.dependencies?.vue || packageJson.devDependencies?.vue) {
                echo "Vue.js project detected, setting port to 8080"
                return [type: 'vuejs', port: 80]
            } else if (packageJson.dependencies?.angular || packageJson.devDependencies?.angular) {
                echo "Angular project detected, setting port to 4200"
                return [type: 'angular', port: 4200]
            } else if (packageJson.dependencies?.nuxt || packageJson.devDependencies?.nuxt) {
                echo "Nuxt.js project detected, setting port to 3000"
                return [type: 'nuxtjs', port: 3000]
            } else if (packageJson.dependencies?.svelte || packageJson.devDependencies?.svelte) {
                echo "Svelte project detected, setting port to 5000"
                return [type: 'svelte', port: 5000]
            } else if (packageJson.dependencies?.express || packageJson.devDependencies?.express) {
                echo "Express project detected, setting port to 3000"
                return [type: 'express', port: 3000]
            } else if (packageJson.dependencies?.nestjs || packageJson.devDependencies?.nestjs) {
                echo "NestJS project detected, setting port to 3000"
                return [type: 'nestjs', port: 3000]
            }
        } else if (fileExists("${projectPath}/index.html")) {
            echo "HTML project detected"
            return [type: 'html', port: 80]
        } else if (fileExists("${projectPath}/index.php")) {
            echo "PHP project detected"
            return [type: 'php', port: 80]
        } else if (fileExists("${projectPath}/pom.xml")) {
            def port = readSpringBootPortFromYaml(projectPath)
            echo "Spring Boot (Maven) project detected, setting port to ${port}"
            return [type: 'springboot-maven', port: port]
        } else if (fileExists("${projectPath}/build.gradle") || fileExists("${projectPath}/build.gradle.kts")) {
            def port = readSpringBootPortFromYaml(projectPath)
            echo "Spring Boot (Gradle) project detected, setting port to ${port}"
            return [type: 'springboot-gradle', port: port]
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

def readSpringBootPortFromYaml(String projectPath) {
    def defaultPort = 8080
    def yamlFilePath = "${projectPath}/src/main/resources/application.yml"

    if (!fileExists(yamlFilePath)) {
        echo "application.yml not found, using default port: ${defaultPort}"
        return defaultPort
    }

    try {
        def yamlContent = readFile(file: yamlFilePath)
        def port = extractPortFromYaml(yamlContent)

        if (port) {
            echo "Port found in application.yml: ${port}"
            return port.toInteger()
        } else {
            echo "Port not defined in application.yml, using default port: ${defaultPort}"
        }
    } catch (Exception e) {
        echo "Error reading application.yml: ${e.message}, using default port: ${defaultPort}"
    }

    return defaultPort
}

def extractPortFromYaml(String yamlContent) {
    // A simple regex to extract the port value from YAML
    def match = yamlContent =~ /(?m)^\s*server:\s*\n\s*port:\s*(\d+)/
    if (match) {
        return match[0][1]
    }
    return 8080
}
