# Vault Dynamic Credentials Deployment Guide

## Overview
This deployment includes proper dependencies and health checks to ensure Vault is ready before configuring it.

## Key Improvements Made

### 1. Health Check Script (`wait_for_vault.sh`)
- Waits for Vault to respond to health checks
- Verifies SSM parameter is available before proceeding
- Prevents Terraform from configuring Vault before it's ready

### 2. Enhanced Vault Initialization (`vault_init.sh`)
- Better error handling and logging
- Proper status checks before proceeding
- Cleanup of sensitive files
- Verification that Vault is unsealed and ready

### 3. Dependency Management
- Added `null_resource.wait_for_vault` to coordinate timing
- All Vault resources now depend on this health check
- Lambda deployment waits for Vault to be fully configured

## Deployment Steps

1. **Initialize Terraform:**
   ```bash
   cd terraform
   terraform init
   ```

2. **Plan the deployment:**
   ```bash
   terraform plan
   ```

3. **Apply the configuration:**
   ```bash
   terraform apply
   ```

## Troubleshooting

### Check Vault Status
If deployment fails, check the Vault initialization logs:
```bash
# Get the instance ID from Terraform output
INSTANCE_ID=$(terraform output -raw vault_instance_id)

# Check CloudWatch logs
aws logs filter-log-events \
  --log-group-name "/aws/ec2/vault-init" \
  --log-stream-names "$INSTANCE_ID" \
  --region us-east-1
```

### Verify SSM Parameter
Check if the root token was stored successfully:
```bash
aws ssm get-parameter --name "/vault/root_token" --with-decryption --region us-east-1
```

### Manual Vault Check
SSH into the Vault instance and check status:
```bash
# SSH to instance (use the generated key)
ssh -i vault-key.pem ubuntu@<vault-ip>

# Check Vault status
export VAULT_ADDR='http://127.0.0.1:8200'
vault status
```

## Security Notes
- This is a demo setup using HTTP and single unseal key
- For production, use HTTPS, multiple unseal keys, and proper secret management
- The root token should be rotated after initial setup