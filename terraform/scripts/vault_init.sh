#!/bin/bash

# Vault Initialization Script
VAULT_VERSION="${vault_version}"

# Update system
apt-get update
apt-get install -y curl unzip

# Install Vault
curl -O https://releases.hashicorp.com/vault/${vault_version}/vault_${vault_version}_linux_amd64.zip
unzip vault_${vault_version}_linux_amd64.zip
mv vault /usr/local/bin/
chmod +x /usr/local/bin/vault

# Create Vault user and directories
useradd --system --home /etc/vault.d --shell /bin/false vault
mkdir -p /etc/vault.d
mkdir -p /var/lib/vault
chown -R vault:vault /etc/vault.d /var/lib/vault

# Create Vault configuration
cat << EOF > /etc/vault.d/vault.hcl
storage "file" {
  path = "/var/lib/vault"
}

listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = 1
}

api_addr = "http://$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4):8200"
ui = true
EOF

chown vault:vault /etc/vault.d/vault.hcl

# Create systemd service
cat << EOF > /etc/systemd/system/vault.service
[Unit]
Description=Vault
Documentation=https://www.vaultproject.io/docs/
Requires=network-online.target
After=network-online.target

[Service]
User=vault
Group=vault
ProtectSystem=full
ProtectHome=read-only
PrivateTmp=yes
PrivateDevices=yes
SecureBits=keep-caps
AmbientCapabilities=CAP_IPC_LOCK
Capabilities=CAP_IPC_LOCK+ep
CapabilityBoundingSet=CAP_SYSLOG CAP_IPC_LOCK
NoNewPrivileges=yes
ExecStart=/usr/local/bin/vault server -config=/etc/vault.d/vault.hcl
ExecReload=/bin/kill --signal HUP \$MAINPID
KillMode=process
KillSignal=SIGINT
Restart=on-failure
RestartSec=5
TimeoutStopSec=30
StartLimitInterval=60
StartLimitBurst=3
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

# Start Vault service
systemctl enable vault
systemctl start vault

# Wait for Vault to start
sleep 5

# Install jq and AWS CLI (for uploading token to SSM)
apt-get install -y jq python3 python3-pip
pip3 install --upgrade awscli

# Install CloudWatch Agent
apt-get install -y wget unzip
CWAGENT_DEB="amazon-cloudwatch-agent.deb"
wget https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb -O $CWAGENT_DEB
dpkg -i $CWAGENT_DEB || true

# Create cloudwatch-agent config to send Vault init logs and cloud-init output
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << CWA
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/vault-init.log",
            "log_group_name": "${vault_log_group}",
            "log_stream_name": "{instance_id}/vault-init"
          },
          {
            "file_path": "/var/log/cloud-init-output.log",
            "log_group_name": "${vault_log_group}",
            "log_stream_name": "{instance_id}/cloud-init-output"
          }
        ]
      }
    }
  }
}
CWA

# Start the CloudWatch Agent
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json -s || true

# Initialize Vault (NOT for production — demo initialization)
export VAULT_ADDR='http://127.0.0.1:8200'
vault operator init -key-shares=1 -key-threshold=1 -format=json | tee /var/log/vault-init.log > /tmp/vault-init.json

# Extract unseal key and root token
UNSEAL_KEY=$(jq -r '.unseal_keys_b64[0]' /tmp/vault-init.json)
ROOT_TOKEN=$(jq -r '.root_token' /tmp/vault-init.json)

# Unseal Vault
vault operator unseal $UNSEAL_KEY

# Store root token into SSM Parameter Store as SecureString
SSM_PARAM_NAME="/vault/root_token"
aws ssm put-parameter --name "$SSM_PARAM_NAME" --value "$ROOT_TOKEN" --type "SecureString" --overwrite --region "${aws_region}"

echo "Vault installation completed and root token stored in SSM at $SSM_PARAM_NAME"
