# Wazuh Docker Swarm CI/CD Pipeline

Automated deployment pipeline for Wazuh SIEM on Docker Swarm with integrated security scanning.

![Pipeline Success](docs/images/pipeline-check.png)

## Overview

![Pipeline Success](docs/images/architecture.png)

This project implements a CI/CD pipeline for deploying Wazuh SIEM to a Docker Swarm cluster using GitHub Actions, Ansible, and Trivy security scanning. The pipeline ensures secure deployments by scanning Docker images for vulnerabilities before deployment.

## Repository Structure

```
wazuh-cires-ci/
├── .github/workflows/
│   └── deploy.yml                 # Main CI/CD pipeline
├── config/
│   ├── certs.yml                  # Certificate generation config
│   ├── wazuh_cluster/
│   │   └── wazuh_manager.conf     # Manager configuration
│   ├── wazuh_indexer/
│   │   ├── wazuh.indexer.yml      # Indexer configuration
│   │   ├── internal_users.yml     # User definitions
│   │   └── wazuh_indexer_ssl_certs/ # SSL certificates
│   └── wazuh_dashboard/
│       ├── opensearch_dashboards.yml
│       └── wazuh.yml              # Dashboard configuration
├── docs/
│   └── images/
│       └── pipeline-check.png     # Pipeline success screenshot
├── wazuh-swarm.yaml              # Docker Swarm stack definition
├── generate-indexer-certs.yml    # Certificate generation compose
├── setup-secrets.sh              # Docker secrets setup script
└── README.md                     # This documentation
```

## Pipeline Overview

The CI/CD pipeline consists of 4 main jobs:

### 1. Configuration Validation (`validate-config`)
- **Duration**: ~30 seconds
- **Purpose**: Validates all required configuration files exist
- **Trigger**: All events (push, PR, manual)

### 2. Security Scanning (`security-scan`)
- **Duration**: ~5-10 minutes (first run), ~2-3 minutes (subsequent)
- **Purpose**: Scans Docker images for vulnerabilities using Trivy
- **Images scanned**:
  - `wazuh/wazuh-manager:4.12.0`
  - `wazuh/wazuh-indexer:4.12.0`
  - `wazuh/wazuh-dashboard:4.12.0`
- **Severity**: Currently set to CRITICAL only with `--exit-code 0` (non-blocking)
- **Output**: SARIF reports uploaded to GitHub Security tab

### 3. Deployment (`deploy`)
- **Duration**: ~5-8 minutes
- **Purpose**: Deploys Wazuh stack to Docker Swarm using Ansible
- **Dependencies**: Requires configuration validation and security scan completion
- **Trigger**: Only on push to main branch
- **Process**:
  1. Copy configuration files to swarm manager
  2. Generate SSL certificates using custom compose file
  3. Create Docker secrets from certificates and configs
  4. Deploy stack using `docker stack deploy`
  5. Wait for services to be ready
  6. Verify dashboard accessibility

### 4. Notification (`notify`)
- **Duration**: ~10 seconds
- **Purpose**: Reports overall pipeline status
- **Provides**: Summary of security scan and deployment results

## Setup Instructions

### Prerequisites

**Docker Swarm Cluster:**
```bash
# Initialize swarm on manager node
docker swarm init

# Join worker nodes (run on each worker)
docker swarm join --token <token> <manager-ip>:2377
```

**Self-Hosted GitHub Runner:**
```bash
# Download and configure runner
mkdir actions-runner && cd actions-runner
curl -o actions-runner-linux-x64-2.319.1.tar.gz -L https://github.com/actions/runner/releases/download/v2.319.1/actions-runner-linux-x64-2.319.1.tar.gz
tar xzf ./actions-runner-linux-x64-2.319.1.tar.gz
./config.sh --url https://github.com/YOUR_USERNAME/YOUR_REPO --token YOUR_TOKEN

# Install as service
sudo ./svc.sh install
sudo ./svc.sh start
```

### Required Tools Installation

**On Self-Hosted Runner:**
```bash
# Essential packages
sudo apt update
sudo apt install -y python3 python3-pip docker.io git curl

# Add user to docker group
sudo usermod -aG docker $USER

# Install Trivy
wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | sudo apt-key add -
echo "deb https://aquasecurity.github.io/trivy-repo/deb $(lsb_release -sc) main" | sudo tee -a /etc/apt/sources.list.d/trivy.list
sudo apt-get update && sudo apt-get install trivy
```

### GitHub Secrets Configuration

Set these secrets in your repository (Settings → Secrets and variables → Actions):

| Secret Name | Description | Example |
|-------------|-------------|---------|
| `SSH_PRIVATE_KEY` | Private SSH key for swarm access | `-----BEGIN OPENSSH PRIVATE KEY-----...` |
| `SWARM_MANAGER_HOST` | IP address of Docker Swarm manager | `192.168.1.100` |
| `SWARM_MANAGER_USER` | SSH username for swarm manager | `ubuntu` |
| `WAZUH_API_PASSWORD` | Password for Wazuh API access | `SecurePassword123!` |
| `INDEXER_PASSWORD` | Password for Wazuh indexer | `IndexerPass456!` |

### SSH Access Setup

**Generate SSH key:**
```bash
ssh-keygen -t rsa -b 4096 -f ~/.ssh/wazuh_ci_key
```

**Add public key to swarm manager:**
```bash
# Copy public key content
cat ~/.ssh/wazuh_ci_key.pub

# On swarm manager
echo "your-public-key-content" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

**Set up passwordless sudo (on swarm manager):**
```bash
echo "$USER ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/$USER
```

## Usage

### Automatic Deployment
Simply push to the main branch:
```bash
git push origin main
```

The pipeline will automatically:
1. Validate configurations
2. Scan images for CRITICAL vulnerabilities (non-blocking)
3. Deploy to Docker Swarm
4. Report results

### Manual Execution
1. Go to Actions tab in GitHub
2. Select "Wazuh Docker Swarm Deployment"
3. Click "Run workflow"
4. Choose branch and click "Run workflow"

## Pipeline Configuration Details

### Security Scanning Configuration
Current Trivy configuration:
```yaml
trivy image \
  --format sarif \
  --output "trivy-results-${SAFE_IMAGE_NAME}.sarif" \
  --severity CRITICAL \
  --timeout 5m \
  --exit-code 0 \
  ${{ matrix.image }}
```

**Key settings:**
- **Severity**: CRITICAL only
- **Exit code**: 0 (non-blocking - scans report but don't fail pipeline)
- **Timeout**: 5 minutes per image
- **Output**: SARIF format uploaded to GitHub Security tab

### Deployment Process
1. **File copying**: Configuration files transferred via Ansible
2. **Certificate generation**: Custom `generate-indexer-certs.yml` compose file
3. **Secrets management**: Docker Swarm secrets for certificates and configs
4. **Stack deployment**: `docker stack deploy -c wazuh-swarm.yaml wazuh`
5. **Health verification**: Service readiness and dashboard accessibility checks

## Monitoring and Troubleshooting

### Pipeline Logs
- **Location**: GitHub Actions → Workflow runs
- **Retention**: 90 days (GitHub default)

### Application Logs
```bash
# Check service status
docker service ls --filter name=wazuh

# View service logs
docker service logs wazuh_wazuh-manager
docker service logs wazuh_wazuh-indexer
docker service logs wazuh_wazuh-dashboard
```

### Security Reports
- **Location**: Repository → Security tab → Code scanning alerts
- **Format**: SARIF reports with detailed vulnerability information

### Common Issues

**1. SSH connection failures:**
```bash
# Test SSH connectivity
ssh -i ~/.ssh/id_rsa user@swarm-manager-ip

# Check SSH key permissions
chmod 600 ~/.ssh/id_rsa
```

**2. Certificate generation failures:**
```bash
# Check certificate generation logs
docker compose -f generate-indexer-certs.yml logs
```

**3. Service deployment issues:**
```bash
# Check stack deployment
docker stack ps wazuh

# Inspect failed services
docker service ps wazuh_service-name --no-trunc
```

**4. Trivy not found:**
```bash
# Verify Trivy installation
trivy --version

# Reinstall if needed
sudo apt-get install trivy
```

## Security Considerations

### Pipeline Security
- Encrypted GitHub secrets for sensitive data
- Self-hosted runner isolation
- Vulnerability scanning before deployment
- Audit logging via GitHub Actions

### Application Security
- TLS encryption for all Wazuh communications
- Certificate management via Docker Swarm secrets
- Network isolation using Docker overlay networks
- Access control through Wazuh internal users

## Customization

### Modifying Security Scan Severity
Edit the `--severity` parameter in `deploy.yml`:
```yaml
--severity CRITICAL,HIGH    # Scan for critical and high
--severity HIGH             # Scan for high only
--severity CRITICAL         # Scan for critical only (current)
```
