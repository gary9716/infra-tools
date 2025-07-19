#!/bin/bash

# Usage: ./fill-env-from-task-def.sh <task-definition-json-file> [env-file] [region]
# Example: ./fill-env-from-task-def.sh .aws/task-definition-staging.json .env ap-southeast-1

set -euo pipefail

JSON_FILE="$1"
ENV_FILE="${2:-.env}"
REGION="${3:-ap-southeast-1}"
SECRET_CACHE_DIR="$(mktemp -d)"

if [ -z "$JSON_FILE" ]; then
  echo "Usage: $0 <task-definition-json-file> [region]"
  exit 1
fi

if [ ! -f "$JSON_FILE" ]; then
  echo "File not found: $JSON_FILE"
  exit 1
fi

# --- Collect all unique Secrets Manager ARNs across all containers ---
SECRET_ARNS=$(jq -r '
  .containerDefinitions // [] |
  .[] | (.secrets // [] | map(select(type == "object" and .valueFrom? and (.valueFrom | startswith("arn:aws:secretsmanager:")))) | .[] | .valueFrom)
' "$JSON_FILE" | sed -E 's|:([^:]+)::?$||' | sort | uniq)

# --- Collect all unique SSM parameter names across all containers ---
SSM_PARAM_NAMES=$(jq -r '
  .containerDefinitions // [] |
  .[] | (.secrets // [] | map(select(type == "object" and .valueFrom? and (.valueFrom | startswith("arn:aws:ssm:")))) | .[] | .valueFrom)
' "$JSON_FILE" | sed -E 's|.*:parameter/?||' | sed 's|^|/|' | sort | uniq)

# --- Pull each secret only once and store in a temp file ---
for ARN in $SECRET_ARNS; do
  if [ -z "$ARN" ]; then
    continue
  fi
  TEMP_FILE_NAME=$(echo "$ARN" | md5 | sed 's/^.*= //')
  CACHE_FILE="$SECRET_CACHE_DIR/$TEMP_FILE_NAME"
  if [ ! -f "$CACHE_FILE" ]; then
    aws secretsmanager get-secret-value --secret-id "$ARN" --region "$REGION" --query 'SecretString' --output text > "$CACHE_FILE"
  fi
done

# Batch fetch SSM parameters (in groups of 10)
SSM_PARAM_FILE="$SECRET_CACHE_DIR/ssm_params.json"
> "$SSM_PARAM_FILE"
PARAM_BATCH=()
COUNT=0
for PARAM in $SSM_PARAM_NAMES; do
  PARAM_BATCH+=("$PARAM")
  COUNT=$((COUNT+1))
  if [ $COUNT -eq 10 ]; then
    aws ssm get-parameters --names "${PARAM_BATCH[@]}" --region "$REGION" --with-decryption --output json >> "$SSM_PARAM_FILE"
    PARAM_BATCH=()
    COUNT=0
  fi
done
if [ ${#PARAM_BATCH[@]} -gt 0 ]; then
  aws ssm get-parameters --names "${PARAM_BATCH[@]}" --region "$REGION" --with-decryption --output json >> "$SSM_PARAM_FILE"
fi

jq -s '{Parameters: map(.Parameters) | add}' "$SSM_PARAM_FILE" > "$SECRET_CACHE_DIR/ssm_params_merged.json"

# --- Process all containers ---
> "$ENV_FILE"  # Truncate the file at the start
CONTAINER_COUNT=$(jq '.containerDefinitions | length' "$JSON_FILE")
for ((i=0; i<CONTAINER_COUNT; i++)); do
  CONTAINER_NAME=$(jq -r ".containerDefinitions[$i].name" "$JSON_FILE")
  echo "" >> "$ENV_FILE"
  echo "# Container: $CONTAINER_NAME" >> "$ENV_FILE"

  # Output environment variables
  ENV_VARS=$(jq -r ".containerDefinitions[$i].environment // [] | .[] | \"\(.name)=\(.value)\"" "$JSON_FILE")
  if [ -n "$ENV_VARS" ]; then
    while IFS= read -r line; do
      # Split line into key and value, then wrap value in double quotes
      key="${line%%=*}"
      value="${line#*=}"
      echo "$key='$value'" >> "$ENV_FILE"
    done <<< "$ENV_VARS"
  fi

  # Output secrets
  jq -c ".containerDefinitions[$i].secrets // [] | map(select(type == \"object\" and .valueFrom?)) | .[]" "$JSON_FILE" | while read -r secret; do
    NAME=$(echo "$secret" | jq -r '.name')
    VALUE_FROM=$(echo "$secret" | jq -r '.valueFrom')

    if [[ "$VALUE_FROM" == arn:aws:secretsmanager:* ]]; then
      BASE_ARN=$(echo "$VALUE_FROM" | sed -E 's|:([^:]+)::?$||')
      SECRET_KEY=$(echo "$VALUE_FROM" | sed -E 's|.*:([^:]+)::?$|\1|')
      TEMP_FILE_NAME=$(echo "$BASE_ARN" | md5 | sed 's/^.*= //')
      CACHE_FILE="$SECRET_CACHE_DIR/$TEMP_FILE_NAME"
      SECRET_JSON=$(cat "$CACHE_FILE")
      VALUE="$(echo "$SECRET_JSON" | jq -r --arg key "$SECRET_KEY" '.[$key]')"
    elif [[ "$VALUE_FROM" == arn:aws:ssm:* ]]; then
      PARAM_NAME=$(echo "$VALUE_FROM" | sed -E 's|.*:parameter/?||')
      if [[ "$PARAM_NAME" != /* ]]; then
        PARAM_NAME="/$PARAM_NAME"
      fi
      VALUE=$(jq -r --arg name "$PARAM_NAME" '.Parameters[] | select(.Name == $name) | .Value' "$SECRET_CACHE_DIR/ssm_params_merged.json")
    else
      echo "Unknown secret type for $NAME: $VALUE_FROM" >&2
      continue
    fi
    PAIR="$NAME='$VALUE'"
    echo "$PAIR" >> "$ENV_FILE"
  done
done

rm -rf "$SECRET_CACHE_DIR"
