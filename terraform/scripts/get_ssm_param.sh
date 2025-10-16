#!/bin/bash
set -e
# Arguments: name region
NAME="$1"
REGION="$2"

if [ -z "$NAME" ]; then
  echo '{"value":""}'
  exit 0
fi

if [ -z "$REGION" ]; then
  REGION="us-east-1"
fi

OUTPUT=$(aws ssm get-parameter --name "$NAME" --with-decryption --region "$REGION" 2>/dev/null || true)
if [ -z "$OUTPUT" ]; then
  # Return empty value, but exit 0 so Terraform doesn't error
  echo '{"value":""}'
  exit 0
fi

# Extract the value using jq; if jq missing, output empty
VALUE=$(echo "$OUTPUT" | jq -r '.Parameter.Value' 2>/dev/null || true)
if [ -z "$VALUE" ] || [ "$VALUE" = "null" ]; then
  echo '{"value":""}'
else
  # Escape the value for JSON - jq -R -s . would be better but keep simple
  printf '{"value":"%s"}' "$(echo "$VALUE" | sed 's/"/\\"/g')"
fi
