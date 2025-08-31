#!/bin/bash
# Create Docker Secrets for Wazuh Swarm deployment from existing config files

set -e

echo "Creating Docker secrets for Wazuh from config/ directory..."

# Verify we're on a swarm manager
if ! docker node ls &>/dev/null; then
    echo "Error: This script must be run on a Docker Swarm manager node"
    exit 1
fi

# Verify config directory exists
if [ ! -d "config" ]; then
    echo "Error: config/ directory not found in current directory"
    echo "Please run this script from the directory containing the config/ folder"
    exit 1
fi

# Function to create secret with error handling
create_secret() {
    local secret_name=$1
    local file_path=$2

    if sudo test -f "$file_path"; then
        if docker secret inspect "$secret_name" >/dev/null 2>&1; then
            echo "Secret $secret_name already exists, removing it first..."
            docker secret rm "$secret_name"
        fi
        echo "Creating secret: $secret_name"
        sudo docker secret create "$secret_name" "$file_path"
    else
        echo "Warning: File $file_path not found, skipping $secret_name"
    fi
}

echo "Creating certificate secrets..."

# Certificate secrets (using exact filenames from your directory)
create_secret "root-ca-pem" "config/wazuh_indexer_ssl_certs/root-ca.pem"
create_secret "root-ca-manager-pem" "config/wazuh_indexer_ssl_certs/root-ca-manager.pem"
create_secret "admin-pem" "config/wazuh_indexer_ssl_certs/admin.pem"
create_secret "admin-key" "config/wazuh_indexer_ssl_certs/admin-key.pem"

# Component certificates
create_secret "wazuh-indexer-pem" "config/wazuh_indexer_ssl_certs/wazuh.indexer.pem"
create_secret "wazuh-indexer-key" "config/wazuh_indexer_ssl_certs/wazuh.indexer-key.pem"
create_secret "wazuh-manager-pem" "config/wazuh_indexer_ssl_certs/wazuh.manager.pem"
create_secret "wazuh-manager-key" "config/wazuh_indexer_ssl_certs/wazuh.manager-key.pem"
create_secret "wazuh-dashboard-pem" "config/wazuh_indexer_ssl_certs/wazuh.dashboard.pem"
create_secret "wazuh-dashboard-key" "config/wazuh_indexer_ssl_certs/wazuh.dashboard-key.pem"

echo "Creating configuration secrets..."

# Configuration file secrets
create_secret "wazuh-indexer-yml" "config/wazuh_indexer/wazuh.indexer.yml"
create_secret "internal-users-yml" "config/wazuh_indexer/internal_users.yml"
create_secret "opensearch-dashboards-yml" "config/wazuh_dashboard/opensearch_dashboards.yml"
create_secret "wazuh-yml" "config/wazuh_dashboard/wazuh.yml"
create_secret "wazuh-manager-conf" "config/wazuh_cluster/wazuh_manager.conf"

echo ""
echo "Docker secrets created successfully!"
echo ""
echo "You can verify the secrets with:"
echo "docker secret ls"
echo ""
echo "Next steps:"
echo "1. Deploy the stack: docker stack deploy -c wazuh-swarm-stack.yml wazuh"
echo "2. Check service status: docker service ls"
echo "3. View service logs: docker service logs wazuh_wazuh-indexer"
echo "4. Initialize indexer security after all services are running"
