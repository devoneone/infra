def call(String inventoryFile, String playbookFile, String namespace, String replicaCount) {
    sh """
    ansible-playbook -i ${inventoryFile} ${playbookFile} -e NAMESPACE=${namespace} -e REPLICA_COUNT=${replicaCount}
    """
}
