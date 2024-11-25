#!/usr/bin/env groovy

def call(String projectPath = '.') {
    echo "Detecting project type for path: ${projectPath}"
    def projectInfo = detectProjectType(projectPath)

    echo "Project info detected: ${projectInfo}"
    echo "Project info type: ${projectInfo?.type}"
    echo "Project info port: ${projectInfo?.port}"

    if (projectInfo) {
        echo "Detected project type: ${projectInfo.type}"
        echo "Detected port: ${projectInfo.port}"

        if (!dockerfileExists(projectPath)) {
            def packageManager = detectPackageManager(projectPath)
            echo "Detected package manager: ${packageManager}"
            writeDockerfile(projectInfo.type, projectPath, packageManager)
        } else {
            echo "Dockerfile already exists at ${projectPath}/Dockerfile, skipping generation."
        }

        echo "Returning project info: ${projectInfo}"
        return projectInfo
    } else {
        error "Unable to detect the project type for ${projectPath}."
    }
}

def dockerfileExists(String projectPath) {
    return fileExists("${projectPath}/Dockerfile")
}

def detectProjectType(String projectPath) {
    echo "Checking for package.json in ${projectPath}"
    if (fileExists("${projectPath}/package.json")) {
        def packageJson = readJSON file: "${projectPath}/package.json"
        echo "package.json contents: ${packageJson}"

        if (packageJson.dependencies?.next || packageJson.devDependencies?.next) {
            echo "Next.js project detected, setting port to 3000"
            return [type: 'nextjs', port: 3000]
        } else if (packageJson.dependencies?.react || packageJson.devDependencies?.react) {
            echo "React project detected, setting port to 3000"
            return [type: 'react', port: 3000]
        }
    } else if (fileExists("${projectPath}/pom.xml")) {
        echo "Spring Boot (Maven) project detected, setting port to 8080"
        return [type: 'springboot-maven', port: 8080]
    } else if (fileExists("${projectPath}/build.gradle") || fileExists("${projectPath}/build.gradle.kts")) {
        echo "Spring Boot (Gradle) project detected, setting port to 8080"
        return [type: 'springboot-gradle', port: 8080]
    } else if (fileExists("${projectPath}/pubspec.yaml")) {
        echo "Flutter project detected, setting port to 8080"
        return [type: 'flutter', port: 8080]
    }

    echo "No recognized project type detected in ${projectPath}"
    return null
}

def detectPackageManager(String projectPath) {
    if (fileExists("${projectPath}/pnpm-lock.yaml")) {
        return 'pnpm'
    } else if (fileExists("${projectPath}/yarn.lock")) {
        return 'yarn'
    } else if (fileExists("${projectPath}/package-lock.json")) {
        return 'npm'
    } else if (fileExists("${projectPath}/bun.lockb")) {
        return 'bun'
    }
    return 'npm'
}

def writeDockerfile(String projectType, String projectPath, String packageManager) {
    try {
        def dockerfileContent = libraryResource "dockerfileTemplates/Dockerfile-${projectType}"
        dockerfileContent = dockerfileContent.replaceAll("\\{\\{packageManager\\}\\}", packageManager)
        writeFile file: "${projectPath}/Dockerfile", text: dockerfileContent
        echo "Dockerfile successfully written for ${projectType} project at ${projectPath}/Dockerfile"
    } catch (Exception e) {
        error "Failed to write Dockerfile for ${projectType} project: ${e.message}"
    }
}
