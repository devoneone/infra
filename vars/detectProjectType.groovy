import org.cloudinator.ProjectTypeDetector

def call(Map config = [:]) {
    def projectRoot = config.projectRoot ?: '.'
    
    def detector = new ProjectTypeDetector(this, projectRoot)
    def projectType = detector.detectProjectType()
    
    echo "Detected project type: ${projectType}"
    
    return [
        type: projectType,
        dockerfile: detector.getDockerfile()
    ]
}

