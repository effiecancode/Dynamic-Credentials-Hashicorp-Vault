#!/bin/bash
set -e

INSTANCE_ID="$1"
REGION="$2"

echo "Checking Vault initialization status for instance $INSTANCE_ID..."

# Check if instance is running
INSTANCE_STATE=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" --region "$REGION" --query 'Reservations[0].Instances[0].State.Name' --output text)
echo "Instance state: $INSTANCE_STATE"

if [ "$INSTANCE_STATE" != "running" ]; then
    echo "Instance is not running"
    echo '{"status": "not_ready"}'
    exit 0
fi

# Check CloudWatch logs for initialization completion
LOG_GROUP="/aws/ec2/vault-init"
LOG_STREAM="$INSTANCE_ID"

# Check if the initialization completed successfully
if aws logs filter-log-events \
    --log-group-name "$LOG_GROUP" \
    --log-stream-names "$LOG_STREAM" \
    --filter-pattern "SUCCESS: Vault installation completed" \
    --region "$REGION" \
    --query 'events[0].message' \
    --output text 2>/dev/null | grep -q "SUCCESS"; then
    echo "Vault initialization completed successfully"
    echo '{"status": "ready"}'
else
    echo "Vault initialization not yet completed"
    echo '{"status": "not_ready"}'
fi