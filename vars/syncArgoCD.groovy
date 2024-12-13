def call(String inventoryFile, String playbookFile, String appName, String tag) {
    sh """
    ansible-playbook -i ${inventoryFile} ${playbookFile} -e CHART_NAME=${appName} -e CHART_VERSION=${tag}
    """
}
