#!/usr/bin/env bash

# Deploy (or update) the web-hello Container App using Azure CLI and the YAML
# template in aca/containerapp.yml.  This script is intended for training
# purposes and demonstrates how to parameterize app deployments via
# environment variables and secrets.  It reads values from a `.env` file in
# the repository root.  See README.md for instructions.

set -euo pipefail

# Determine the root of the repository relative to this script
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(dirname "$SCRIPT_DIR")

# Load environment variables from .env.  Users should not commit secrets to
# version control; this file is ignored by default.  You can override the
# path by setting ENV_FILE.
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

# Validate required variables
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

# Optionally set the subscription if provided
if [[ -n "${SUBSCRIPTION_ID:-}" ]]; then
  az account set --subscription "$SUBSCRIPTION_ID"
fi

# Resolve the environment resource ID
ENV_ID=$(az containerapp env show \
  --name "$ACA_ENVIRONMENT" \
  --resource-group "$RESOURCE_GROUP" \
  --query id -o tsv)
if [[ -z "$ENV_ID" ]]; then
  echo "Failed to resolve Container Apps environment '$ACA_ENVIRONMENT' in '$RESOURCE_GROUP'" >&2
  exit 1
fi

# Default optional variables
CPU=${CPU:-"0.5"}
MEMORY=${MEMORY:-"1Gi"}
APP_ENV=${APP_ENV:-"production"}
MIN_REPLICAS=${MIN_REPLICAS:-"1"}
MAX_REPLICAS=${MAX_REPLICAS:-"5"}
HTTP_CONCURRENCY=${HTTP_CONCURRENCY:-"50"}

# Determine secrets.  Prefer Key Vault reference if URI and identity are provided.
SECRET_ARG=""
if [[ -n "${DB_SECRET_URI:-}" ]] && [[ -n "${IDENTITY_RESOURCE_ID:-}" ]]; then
  # Use Key Vault secret reference as recommended in the docs【209614643635596†L435-L505】
  SECRET_ARG="db-connection-string=keyvaultref:${DB_SECRET_URI},identityref:${IDENTITY_RESOURCE_ID}"
elif [[ -n "${DB_CONNECTION_STRING:-}" ]]; then
  # Directly set the secret value (not recommended for production)
  SECRET_ARG="db-connection-string=${DB_CONNECTION_STRING}"
else
  echo "Warning: neither DB_SECRET_URI nor DB_CONNECTION_STRING is set. The app will be deployed without a database connection string." >&2
fi

# Prepare the YAML by substituting variables.  We use envsubst to replace
# placeholders in the template.  Only the variables present in the template
# need to be exported.
export ENVIRONMENT_ID="$ENV_ID"
export IMAGE CPU MEMORY APP_ENV MIN_REPLICAS MAX_REPLICAS HTTP_CONCURRENCY APP_NAME

TEMPLATE_FILE="$REPO_ROOT/aca/containerapp.yml"
TMP_YAML="$(mktemp)"
envsubst < "$TEMPLATE_FILE" > "$TMP_YAML"

# Check whether the app already exists
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