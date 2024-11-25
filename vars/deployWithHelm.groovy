def call(String inventoryFile, String playbookFile, String chartName, String releaseName, String chartVersion, String valuesFile, String namespace) {
    sh """
    ansible-playbook -i ${inventoryFile} ${playbookFile} \
    -e "chart_name=${chartName}" \
    -e "release_name=${releaseName}" \
    -e "chart_version=${chartVersion}" \
    -e "values_file=${valuesFile}" \
    -e "namespace=${namespace}"
    """
}

