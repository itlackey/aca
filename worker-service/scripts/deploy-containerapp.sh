#!/usr/bin/env bash

# Deploy or update the worker-service Container App using Azure CLI.  This
# script follows the same pattern as the web-hello deploy script but includes
# additional variables specific to a background worker.  It reads a `.env`
# file from the repository root and uses envsubst to fill in the YAML
# template before invoking `az containerapp create` or `az containerapp update`.

set -euo pipefail

# Resolve directories
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(dirname "$SCRIPT_DIR")

# Load environment variables
ENV_FILE=${ENV_FILE:-"$REPO_ROOT/.env"}
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  set -o allexport
  source "$ENV_FILE"
  set +o allexport
else
  echo "Missing environment file: $ENV_FILE" >&2
  exit 1
fi

# Required variables
required_vars=(
  RESOURCE_GROUP
  ACA_ENVIRONMENT
  APP_NAME
  IMAGE
)
missing=false
for var in "${required_vars[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    echo "Error: $var is not set" >&2
    missing=true
  fi
done
if [[ "$missing" == true ]]; then
  exit 1
fi

# Set subscription if provided
if [[ -n "${SUBSCRIPTION_ID:-}" ]]; then
  az account set --subscription "$SUBSCRIPTION_ID"
fi

# Resolve environment resource ID
ENV_ID=$(az containerapp env show \
  --name "$ACA_ENVIRONMENT" \
  --resource-group "$RESOURCE_GROUP" \
  --query id -o tsv)
if [[ -z "$ENV_ID" ]]; then
  echo "Failed to resolve Container Apps environment '$ACA_ENVIRONMENT' in '$RESOURCE_GROUP'" >&2
  exit 1
fi

# Defaults for optional variables
CPU=${CPU:-"0.25"}
MEMORY=${MEMORY:-"0.5Gi"}
APP_ENV=${APP_ENV:-"production"}
MESSAGE=${MESSAGE:-"Hello from worker-service!"}
INTERVAL_SECONDS=${INTERVAL_SECONDS:-"10"}
MIN_REPLICAS=${MIN_REPLICAS:-"1"}
MAX_REPLICAS=${MAX_REPLICAS:-"3"}
CPU_UTILIZATION=${CPU_UTILIZATION:-"50"}

# Determine secret value or Key Vault reference
SECRET_ARG=""
if [[ -n "${DB_SECRET_URI:-}" ]] && [[ -n "${IDENTITY_RESOURCE_ID:-}" ]]; then
  SECRET_ARG="db-connection-string=keyvaultref:${DB_SECRET_URI},identityref:${IDENTITY_RESOURCE_ID}"
elif [[ -n "${DB_CONNECTION_STRING:-}" ]]; then
  SECRET_ARG="db-connection-string=${DB_CONNECTION_STRING}"
else
  echo "Warning: neither DB_SECRET_URI nor DB_CONNECTION_STRING is set.  The worker will run without a database connection string." >&2
fi

# Export variables for envsubst
export ENVIRONMENT_ID="$ENV_ID" IMAGE CPU MEMORY APP_ENV MESSAGE INTERVAL_SECONDS MIN_REPLICAS MAX_REPLICAS CPU_UTILIZATION APP_NAME

# Render the YAML template
TEMPLATE_FILE="$REPO_ROOT/aca/containerapp.yml"
TMP_YAML="$(mktemp)"
envsubst < "$TEMPLATE_FILE" > "$TMP_YAML"

# Check for existence of the container app
set +e
az containerapp show --name "$APP_NAME" --resource-group "$RESOURCE_GROUP" --only-show-errors &> /dev/null
exists=$?
set -e

if [[ $exists -eq 0 ]]; then
  echo "Updating existing container app '$APP_NAME'"
  az containerapp update \
    --name "$APP_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --yaml "$TMP_YAML" \
    ${SECRET_ARG:+--secrets "$SECRET_ARG"} \
    --only-show-errors
else
  echo "Creating new container app '$APP_NAME'"
  az containerapp create \
    --name "$APP_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --environment "$ACA_ENVIRONMENT" \
    --yaml "$TMP_YAML" \
    ${SECRET_ARG:+--secrets "$SECRET_ARG"} \
    --only-show-errors
fi

# Clean up temporary file
rm -f "$TMP_YAML"

echo "Deployment complete: $APP_NAME"