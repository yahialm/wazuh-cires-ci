# Wazuh Docker Swarm CI/CD Pipeline

This project implements an automated deployment pipeline for Wazuh SIEM on Docker Swarm with integrated security scanning and validation testing.

## Architecture Overview

The solution consists of:
- **3-node Docker Swarm cluster** (Manager, Indexer, Dashboard)
- **GitHub Actions CI/CD pipeline** with self-hosted runner
- **Security scanning** with Trivy vulnerability scanner
- **Automated deployment** using Ansible
- **End-to-end testing** with Selenium

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
├── tests/
│   └── test_dashboard.py          # Selenium tests
├── wazuh-swarm.yaml              # Docker Swarm stack definition
├── generate-indexer-certs.yml    # Certificate generation compose
├── setup-secrets.sh              # Docker secrets setup script
└── README.md                     # This documentation
```

## CI/CD Pipeline Overview

The pipeline consists of 4 main jobs that run in sequence:

### 1. Configuration Validation
- **Purpose**: Validates all required configuration files exist
- **Runtime**: ~30 seconds
- **Trigger**: All events (push, PR, manual)

### 2. Security Scanning (Trivy)
- **Purpose**: Scans Docker images for vulnerabilities
- **Runtime**: ~5-10 minutes (first run), ~2-3 minutes (subsequent)
- **Behavior**: 
  - Scans 3 Wazuh images in parallel
  - Configurable severity levels (HIGH, CRITICAL, or both)
  - Can block or just report based on workflow parameters
- **Trigger**: All events

### 3. Deployment
- **Purpose**: Deploys Wazuh stack to Docker Swarm
- **Runtime**: ~5-8 minutes
- **Dependencies**: Requires security scan to pass (if blocking enabled)
- **Trigger**: Only on push to main branch

### 4. Notification & Testing
- **Purpose**: Reports deployment status and runs validation tests
- **Runtime**: ~2-3 minutes
- **Includes**: Selenium dashboard accessibility test

## Key Features

### Security-First Approach
- **Pre-deployment vulnerability scanning** prevents vulnerable images from reaching production
- **Configurable security policies** allow different severity thresholds
- **Emergency override capability** for critical hotfixes
- **Integration with GitHub Security tab** for vulnerability tracking

### Flexible Deployment Options
The pipeline supports different execution modes:

**Automatic (Push/PR):**
- Uses default settings (HIGH severity blocking)
- Fully automated security-gated deployment

**Manual (Workflow Dispatch):**
- Configurable vulnerability blocking: `true/false`
- Configurable severity levels: `HIGH`, `CRITICAL,HIGH`, `CRITICAL`
- Useful for emergency deployments or testing

### Self-Hosted Runner Benefits
- **No timeout limitations** (unlike GitHub hosted runners)
- **Persistent tool installation** (Trivy, Ansible, Docker)
- **Network access** to internal infrastructure
- **Cost efficiency** for frequent builds

## Setup Instructions

### 1. Infrastructure Prerequisites

**Docker Swarm Cluster:**
```bash
# On manager node
docker swarm init

# On worker nodes
docker swarm join --token <token> <manager-ip>:2377
```

**Self-Hosted Runner Setup:**
```bash
# Download and configure GitHub Actions runner
mkdir actions-runner && cd actions-runner
curl -o actions-runner-linux-x64-2.319.1.tar.gz -L https://github.com/actions/runner/releases/download/v2.319.1/actions-runner-linux-x64-2.319.1.tar.gz
tar xzf ./actions-runner-linux-x64-2.319.1.tar.gz
./config.sh --url https://github.com/YOUR_USERNAME/YOUR_REPO --token YOUR_TOKEN

# Install as service
sudo ./svc.sh install
sudo ./svc.sh start
```

### 2. Required Tools Installation

**On Self-Hosted Runner:**
```bash
# Essential tools
sudo apt update
sudo apt install -y python3 python3-pip docker.io git curl

# Trivy security scanner
wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | sudo apt-key add -
echo "deb https://aquasecurity.github.io/trivy-repo/deb $(lsb_release -sc) main" | sudo tee -a /etc/apt/sources.list.d/trivy.list
sudo apt-get update && sudo apt-get install trivy

# Selenium dependencies
sudo apt install -y chromium-browser chromium-chromedriver
pip3 install selenium pytest
```

### 3. GitHub Secrets Configuration

Configure these secrets in your repository settings:

| Secret Name | Description | Example Value |
|-------------|-------------|---------------|
| `SSH_PRIVATE_KEY` | Private SSH key for swarm access | `-----BEGIN OPENSSH PRIVATE KEY-----...` |
| `SWARM_MANAGER_HOST` | IP address of Docker Swarm manager | `192.168.1.100` |
| `SWARM_MANAGER_USER` | SSH username for swarm manager | `ubuntu` |
| `WAZUH_API_PASSWORD` | Password for Wazuh API access | `SecurePassword123!` |
| `INDEXER_PASSWORD` | Password for Wazuh indexer | `IndexerPass456!` |

### 4. SSH Access Setup

**Generate SSH key pair:**
```bash
ssh-keygen -t rsa -b 4096 -f ~/.ssh/wazuh_ci_key
```

**Add public key to swarm manager:**
```bash
# Copy public key content
cat ~/.ssh/wazuh_ci_key.pub

# On swarm manager
echo "your-public-key-content" >> ~/.ssh/authorized_keys
```

**Set up passwordless sudo (on swarm manager):**
```bash
echo "$USER ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/$USER
```

## Usage Examples

### Standard Deployment
```bash
# Simply push to main branch
git push origin main

# Pipeline will:
# 1. Validate configurations
# 2. Scan for HIGH severity vulnerabilities
# 3. Deploy if scans pass
# 4. Run validation tests
```

### Emergency Deployment (Bypass Security)
1. Go to Actions → Run workflow
2. Set "Block on vulnerabilities" to `false`
3. Choose severity level
4. Click "Run workflow"

### Custom Security Threshold
1. Go to Actions → Run workflow  
2. Set "Block on vulnerabilities" to `true`
3. Set "Severity level" to `CRITICAL,HIGH`
4. Click "Run workflow"

## Pipeline Stages Deep Dive

### Security Scanning Details

**What gets scanned:**
- `wazuh/wazuh-manager:4.12.0`
- `wazuh/wazuh-indexer:4.12.0` 
- `wazuh/wazuh-dashboard:4.12.0`

**Scanning process:**
1. **Parallel execution** - all 3 images scanned simultaneously
2. **Database updates** - vulnerability database updated automatically
3. **SARIF output** - results uploaded to GitHub Security tab
4. **Blocking logic** - pipeline fails if configured severity threshold exceeded

**Trivy configuration:**
```bash
trivy image \
  --format sarif \
  --output results.sarif \
  --severity HIGH \
  --timeout 10m \
  --exit-code 1 \
  your-image:tag
```

### Deployment Process

**Certificate Generation:**
- Uses custom `generate-indexer-certs.yml` compose file
- Generates SSL certificates for all Wazuh components
- Stores certificates in Docker Swarm secrets

**Service Deployment:**
```bash
# Remove existing stack
docker stack rm wazuh

# Deploy new stack
docker stack deploy -c wazuh-swarm.yaml wazuh
```

**Health Checks:**
- Service availability verification
- Dashboard accessibility test (HTTP 200/302)
- API endpoint validation

## Monitoring and Troubleshooting

### Common Issues

**1. Security scan failures:**
```bash
# Check vulnerability details
trivy image --severity HIGH wazuh/wazuh-manager:4.12.0

# View GitHub Security tab for detailed reports
```

**2. SSH connection issues:**
```bash
# Test SSH connectivity
ssh -i ~/.ssh/id_rsa user@swarm-manager-ip

# Verify SSH key in GitHub secrets matches local key
```

**3. Certificate generation failures:**
```bash
# Check certificate container logs
docker compose -f generate-indexer-certs.yml logs

# Verify config/certs.yml exists and is properly formatted
```

**4. Deployment failures:**
```bash
# Check service status
docker service ls --filter name=wazuh

# View service logs
docker service logs wazuh_wazuh-manager
docker service logs wazuh_wazuh-indexer
docker service logs wazuh_wazuh-dashboard
```

### Log Locations

**Pipeline logs:** GitHub Actions → Your workflow run
**Application logs:** 
```bash
docker service logs wazuh_wazuh-manager
docker service logs wazuh_wazuh-indexer  
docker service logs wazuh_wazuh-dashboard
```

**Security scan results:** Repository → Security tab → Code scanning alerts

### Performance Optimization

**Runner performance:**
- Use SSD storage for Docker images
- Ensure adequate RAM (8GB+ recommended)
- Stable network connection to Docker Hub

**Pipeline optimization:**
- Security scans run in parallel (matrix strategy)
- Trivy database cached after first run
- Ansible facts gathering optimized

## Security Considerations

### Pipeline Security
- **Secret management** via GitHub encrypted secrets
- **Network isolation** through self-hosted runner
- **Vulnerability scanning** before deployment
- **Audit logging** via GitHub Actions logs

### Application Security  
- **TLS encryption** for all Wazuh communications
- **Certificate rotation** supported via pipeline re-run
- **Access control** through Wazuh internal user management
- **Network security** via Docker Swarm overlay networks

### Compliance Features
- **Vulnerability tracking** with GitHub Security integration
- **Deployment approval** via security gate mechanisms
- **Change logging** through Git commit history
- **Access auditing** via GitHub Actions run logs

## Extension Points

### Adding New Tests
Create additional test files in the `tests/` directory:
```python
# tests/test_api.py
def test_wazuh_api_health():
    # API health check implementation
    pass
```

### Custom Security Policies
Modify the Trivy scanning step to include custom rules:
```yaml
- name: Custom security scan
  run: |
    trivy image --policy custom-policy.rego your-image:tag
```

### Additional Deployment Targets
Extend the pipeline to support multiple environments:
```yaml
deploy-staging:
  if: github.ref == 'refs/heads/develop'
  # staging deployment steps
  
deploy-production:  
  if: github.ref == 'refs/heads/main'
  # production deployment steps
```

## Contributing

### Development Workflow
1. Fork the repository
2. Create feature branch: `git checkout -b feature/your-feature`
3. Make changes and test locally
4. Submit pull request

### Testing Changes
- Use workflow_dispatch with blocking disabled for testing
- Validate configuration changes locally before committing
- Run security scans on any new Docker images

### Code Standards
- YAML files: 2-space indentation
- Shell scripts: Follow shellcheck recommendations  
- Python tests: Follow PEP 8 style guidelines
