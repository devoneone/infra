def call(String projectDir = '.', String configFile = 'resources/org/cloudinator/projectTypeDetectorConfig.yaml') {
    def detector = new org.cloudinator.ProjectTypeDetector()
    return detector.detect(projectDir, configFile)
}
