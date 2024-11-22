package org.cloudinator

import groovy.yaml.YamlSlurper
import groovy.transform.CompileStatic

@CompileStatic
class ProjectTypeDetector {

    // Load the project type configuration from a YAML file
    static Map<String, List<String>> loadConfig(String configFile) {
        def config = new YamlSlurper().parse(new File(configFile))
        return config.collectEntries { key, value -> 
            [key.capitalize(), value.files]
        }
    }

    // Detect the project type based on configuration and existing files in the project directory
    static String detect(String projectDir, String configFile = 'resources/org/cloudinator/projectTypeDetectorConfig.yaml') {
        Map<String, List<String>> config = loadConfig(configFile)
        config.each { projectType, files ->
            if (files.every { new File(projectDir, it).exists() }) {
                return projectType
            }
        }
        return "Unknown" // If no known files are found, return Unknown
    }
}
