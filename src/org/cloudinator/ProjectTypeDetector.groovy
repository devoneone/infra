package org.cloudinator

import groovy.yaml.YamlSlurper

class ProjectTypeDetector {
    def script
    def projectRoot
    def config

    ProjectTypeDetector(script, projectRoot) {
        this.script = script
        this.projectRoot = projectRoot
        this.config = loadConfig()
    }

    private def loadConfig() {
        def configFile = this.script.libraryResource 'org/cloudinator/projectTypeDetectorConfig.yaml'
        return new YamlSlurper().parseText(configFile)
    }

    def detectProjectType() {
        for (def projectType in config.projectTypes) {
            if (checkForFiles(projectType.files)) {
                return projectType.name
            }
        }
        return "unknown"
    }

    private boolean checkForFiles(files) {
        return files.every { file ->
            def path = "${projectRoot}/${file}"
            script.fileExists(path)
        }
    }

    def getDockerfile() {
        def projectType = detectProjectType()
        def dockerfileTemplate = "Dockerfile-${projectType}"
        return this.script.libraryResource "dockerfileTemplates/${dockerfileTemplate}"
    }
}

