def call(String inventoryFile, String playbookFile, String namespace) {
    sh """
    ansible-playbook -i ${inventoryFile} ${playbookFile} -e NAMESPACE=${namespace}
    """
}
