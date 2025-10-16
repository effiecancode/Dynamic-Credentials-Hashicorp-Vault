#!/bin/bash
set -e

VAULT_IP="$1"
SSM_PARAM="$2"
REGION="$3"
MAX_ATTEMPTS=30
ATTEMPT=0

echo "Waiting for Vault at $VAULT_IP to be ready and SSM parameter $SSM_PARAM to be available..."

while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    ATTEMPT=$((ATTEMPT + 1))
    echo "Attempt $ATTEMPT/$MAX_ATTEMPTS"
    
    # Check if Vault is responding
    if curl -s -f "http://$VAULT_IP:8200/v1/sys/health" > /dev/null 2>&1; then
        echo "Vault is responding to health checks"
        
        # Check if SSM parameter exists
        if aws ssm get-parameter --name "$SSM_PARAM" --with-decryption --region "$REGION" > /dev/null 2>&1; then
            echo "SSM parameter $SSM_PARAM is available"
            echo '{"ready": "true"}'
            exit 0
        else
            echo "SSM parameter not yet available"
        fi
    else
        echo "Vault not yet responding"
    fi
    
    sleep 10
done

echo "Timeout waiting for Vault to be ready"
echo '{"ready": "false"}'
exit 1