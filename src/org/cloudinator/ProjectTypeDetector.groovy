package org.cloudinator

class ProjectTypeDetector {

    static String detectProjectType(String projectPath) {
        if (fileExists("${projectPath}/package.json")) {
            def packageJson = readJSON file: "${projectPath}/package.json"
            if (packageJson.dependencies?.'next') {
                return 'nextjs'
            } else if (packageJson.dependencies?.'react') {
                return 'react'
            }
        } else if (fileExists("${projectPath}/pom.xml")) {
            return 'springboot-maven'
        } else if (fileExists("${projectPath}/build.gradle")) {
            return 'springboot-gradle'
        } else if (fileExists("${projectPath}/pubspec.yaml")) {
            return 'flutter'
        }
        return null
    }

    static String detectPackageManager(String projectPath) {
        if (fileExists("${projectPath}/package-lock.json")) {
            return 'npm'
        } else if (fileExists("${projectPath}/yarn.lock")) {
            return 'yarn'
        } else if (fileExists("${projectPath}/pnpm-lock.yaml")) {
            return 'pnpm'
        } else if (fileExists("${projectPath}/bun.lockb")) {
            return 'bun'
        }
        return 'npm'
    }

    static void writeDockerfile(String projectType, String projectPath, String packageManager) {
        try {
            def dockerfileContent = libraryResource "dockerfileTemplates/Dockerfile-${projectType}"
            dockerfileContent = dockerfileContent.replaceAll("\\{\\{packageManager\\}\\}", packageManager)
            writeFile file: "${projectPath}/Dockerfile", text: dockerfileContent
            echo "Dockerfile successfully written for ${projectType} project at ${projectPath}/Dockerfile"
        } catch (Exception e) {
            error "Failed to write Dockerfile for ${projectType} project: ${e.message}"
        }
    }
}
