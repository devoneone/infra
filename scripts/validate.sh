if [ -z "$DB_NAME" ] || [ -z "$DB_TYPE" ] || [ -z "$DB_VERSION" ] || [ -z "$NAMESPACE" ]; then
    echo "❌ Error: Missing required parameters"
    echo "Usage: $0 DB_NAME DB_TYPE DB_VERSION NAMESPACE [DB_PASSWORD] [DB_USERNAME] [DOMAIN_NAME] [STORAGE_SIZE] [PORT]"
    exit 1
fi

# Set MySQL-specific defaults
if [ "${DB_TYPE}" == "mysql" ]; then
    DB_PASSWORD=${DB_PASSWORD:-rootpassword}
    DB_USERNAME=${DB_USERNAME:-defaultuser}
fi