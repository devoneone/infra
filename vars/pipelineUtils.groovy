def checkoutRepo(String repoUrl, String branch) {
    git branch: branch, url: repoUrl
}

def updateDependencies() {
    if (fileExists('package.json')) {
        sh 'npm update --save && npm install'
    } else if (fileExists('pom.xml')) {
        sh 'mvn versions:use-latest-versions'
    } else if (fileExists('build.gradle') || fileExists('build.gradle.kts')) {
        sh 'gradle useLatestVersions'
    }
}

def runSonarQubeAnalysis(String projectKey, String sonarToken) {
    def scannerHome = tool 'SonarScanner'
    withSonarQubeEnv('SonarQube') {
        sh """
            ${scannerHome}/bin/sonar-scanner \
            -Dsonar.projectKey=${projectKey} \
            -Dsonar.sources=. \
            -Dsonar.host.url=${SONAR_HOST_URL} \
            -Dsonar.login=${sonarToken}
        """
    }
}

def buildAndPushDockerImage(String imageName, String imageTag, String credentialsId) {
    withCredentials([usernamePassword(credentialsId: credentialsId, passwordVariable: 'DOCKER_PWD', usernameVariable: 'DOCKER_USER')]) {
        sh "echo $DOCKER_PWD | docker login -u $DOCKER_USER --password-stdin"
        sh "docker build -t ${imageName}:${imageTag} ."
        sh "docker push ${imageName}:${imageTag}"
    }
}

def runTrivyScan(String imageName, String imageTag, String severity, String ignoreUnfixed, int threshold) {
    def trivyStatus = sh(
        script: """
            trivy image --severity ${severity} \
            --exit-code 0 \
            --ignore-unfixed=${ignoreUnfixed} \
            --format json \
            --output trivy-results.json \
            ${imageName}:${imageTag}
        """,
        returnStatus: true
    )

    def trivyResults = readJSON file: 'trivy-results.json'
    def vulnerabilitiesCount = trivyResults.Results.collect { it.Vulnerabilities?.size() ?: 0 }.sum()

    echo "Total vulnerabilities found: ${vulnerabilitiesCount}"

    if (vulnerabilitiesCount > threshold) {
        input message: "High number of vulnerabilities (${vulnerabilitiesCount}) detected. Review the report and decide whether to proceed.", ok: "Proceed"
    } else if (vulnerabilitiesCount > 0) {
        echo "Number of vulnerabilities (${vulnerabilitiesCount}) is within acceptable range. Automatically proceeding."
    } else {
        echo "No vulnerabilities found."
    }
}

def runAnsiblePlaybook(String inventory, String playbook, Map<String, String> extraVars) {
    def extraVarsString = extraVars.collect { k, v -> "-e \"${k}=${v}\"" }.join(' ')
    sh "ansible-playbook -i ${inventory} ${playbook} ${extraVarsString}"
}

return this

