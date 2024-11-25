def call(String inventoryFile, String playbookFile, String appName, String image, String namespace, String filePath, String domainName, String email, String port) {
    sh """
    ansible-playbook -i ${inventoryFile} ${playbookFile} \
    -e "APP_NAME=${appName}" \
    -e "IMAGE=${image}" \
    -e "NAMESPACE=${namespace}" \
    -e "FILE_Path=${filePath}" \
    -e "DOMAIN_NAME=${domainName}" \
    -e "EMAIL=${email}" \
    -e "PORT=${port}"
    """
}

