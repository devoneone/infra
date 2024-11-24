def call(String imageName, String imageTag, String severity = "HIGH,CRITICAL", String exitCode = "0", String ignoreUnfixed = "true", int vulnThreshold = 5) {
    def trivyStatus = sh(
        script: """
            trivy image --severity ${severity} \
            --exit-code ${exitCode} \
            --ignore-unfixed=${ignoreUnfixed} \
            --format json \
            --output trivy-results.json \
            ${imageName}:${imageTag}
        """,
        returnStatus: true
    )

    def trivyResults = readJSON file: 'trivy-results.json'
    def vulnerabilitiesCount = trivyResults.Results.collect { it.Vulnerabilities?.size() ?: 0 }.sum()

    if (vulnerabilitiesCount > vulnThreshold) {
        input message: "High number of vulnerabilities (${vulnerabilitiesCount}) detected. Review the report and decide whether to proceed.", ok: "Proceed"
    } else if (vulnerabilitiesCount > 0) {
        echo "Number of vulnerabilities (${vulnerabilitiesCount}) is within acceptable range. Automatically proceeding."
    } else {
        echo "No vulnerabilities found."
    }

    return vulnerabilitiesCount
}

