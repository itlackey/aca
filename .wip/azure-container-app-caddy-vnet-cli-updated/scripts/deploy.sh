#!/usr/bin/env bash

##
# deploy.sh
#
# This script deploys the container apps and Caddy reverse proxy on top
# of the shared infrastructure provisioned by `create-resources.sh`.
# It assumes the resource group, virtual network, subnets, storage
# account, Private Endpoint, Private DNS zone and Container Apps
# environment already exist.  See the README for details on running
# `create-resources.sh` first.
#
# High‑level steps:
# 1. Register the Azure Files share as environment storage if not
#    already registered【885288297229663†L620-L627】.
# 2. Deploy two internal container apps (app1 and app2) using the
#    smallest supported CPU/memory combinations【344094499861713†L3038-L3041】.
# 3. Upload the Caddyfile to the Azure Files share.
# 4. Render a YAML template for the Caddy reverse proxy and deploy or
#    update the app using the CLI【885288297229663†L732-L736】.
# 5. Print the internal FQDNs of the back‑end services and the
#    external FQDN of the Caddy proxy.
#
# Before running this script you must install the Azure CLI and the
# Container Apps extension (`az extension add --name containerapp`).
# Ensure you have run `create-resources.sh` and that the `.env` file
# contains the necessary variables.

set -euo pipefail

##
# Load configuration from .env
#
# Copy `.env.example` to `.env` and adjust values for your deployment.
ENV_FILE=${ENV_FILE:-"$(dirname "$0")/.env"}
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  set -o allexport
  source "$ENV_FILE"
  set +o allexport
else
  echo "Environment file '$ENV_FILE' not found. Please run create-resources.sh first and copy .env.example to .env." >&2
  exit 1
fi

##
# Required variables
#
required_vars=(
  RESOURCE_GROUP
  LOCATION
  ACA_ENVIRONMENT
  STORAGE_ACCOUNT_NAME
  FILE_SHARE_NAME
  CADDY_APP_NAME
  APP1_NAME
  APP2_NAME
  STORAGE_NAME
  PUBLIC_DOMAIN
  LETS_ENCRYPT_EMAIL
)
missing=false
for var in "${required_vars[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    echo "Error: required variable '$var' is not set in $ENV_FILE" >&2
    missing=true
  fi
done
if [[ "$missing" == true ]]; then
  exit 1
fi

##
# Configure the Azure subscription if provided
if [[ -n "${SUBSCRIPTION_ID:-}" ]]; then
  echo "Using subscription $SUBSCRIPTION_ID"
  az account set --subscription "$SUBSCRIPTION_ID"
fi

# ----------------------------------------------------------------------------
# Helper functions

function resource_group_exists() {
  local group=$1
  az group show --name "$group" --only-show-errors > /dev/null 2>&1
}

function vnet_exists() {
  local group=$1 vnet=$2
  az network vnet show --resource-group "$group" --name "$vnet" --only-show-errors > /dev/null 2>&1
}

function subnet_exists() {
  local group=$1 vnet=$2 subnet=$3
  az network vnet subnet show --resource-group "$group" --vnet-name "$vnet" --name "$subnet" --only-show-errors > /dev/null 2>&1
}

function workspace_exists() {
  local group=$1 name=$2
  az monitor log-analytics workspace show --resource-group "$group" --workspace-name "$name" --only-show-errors > /dev/null 2>&1
}

function container_env_exists() {
  local group=$1 name=$2
  az containerapp env show --resource-group "$group" --name "$name" --only-show-errors > /dev/null 2>&1
}


function storage_account_exists() {
  local group=$1 name=$2
  az storage account show --resource-group "$group" --name "$name" --only-show-errors > /dev/null 2>&1
}


# ----------------------------------------------------------------------------
# Helper functions

function container_app_exists() {
  local group=$1 name=$2
  az containerapp show --resource-group "$group" --name "$name" --only-show-errors > /dev/null 2>&1
}

# ----------------------------------------------------------------------------
# Step 1: Register the Azure Files share with the environment

echo "[1/4] Ensuring Azure Files share '$FILE_SHARE_NAME' is registered with environment storage '$STORAGE_NAME'..."
# Retrieve storage account key
SA_KEY=$(az storage account keys list --resource-group "$RESOURCE_GROUP" --account-name "$STORAGE_ACCOUNT_NAME" --query '[0].value' -o tsv)

# Create share if not exists
if ! az storage share exists --account-name "$STORAGE_ACCOUNT_NAME" --account-key "$SA_KEY" --name "$FILE_SHARE_NAME" --query exists -o tsv | grep -q true; then
  az storage share create --account-name "$STORAGE_ACCOUNT_NAME" --account-key "$SA_KEY" --name "$FILE_SHARE_NAME" --output none
  echo "Created file share '$FILE_SHARE_NAME'."
fi

# Configure environment storage.  We always set the access mode to
# ReadWrite because Caddy requires write access to persist ACME
# account data and certificates.  If the storage mapping already
# exists, invoking 'env storage set' with the same parameters is
# idempotent and will update the access mode if needed.
az containerapp env storage set \
  --name "$ACA_ENVIRONMENT" \
  --resource-group "$RESOURCE_GROUP" \
  --storage-name "$STORAGE_NAME" \
  --storage-type AzureFile \
  --azure-file-account-name "$STORAGE_ACCOUNT_NAME" \
  --azure-file-account-key "$SA_KEY" \
  --azure-file-share-name "$FILE_SHARE_NAME" \
  --access-mode ReadWrite \
  --output none
echo "Configured environment storage '$STORAGE_NAME' for Azure Files with ReadWrite access."

# ----------------------------------------------------------------------------
# Step 2: Deploy internal backend apps

echo "[2/4] Deploying internal backend container apps..."

if ! container_app_exists "$RESOURCE_GROUP" "$APP1_NAME"; then
  az containerapp create \
    --name "$APP1_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --environment "$ACA_ENVIRONMENT" \
    --image nginxdemos/hello \
    --target-port 80 \
    --ingress internal \
    --cpu 0.25 \
    --memory 0.5Gi \
    --min-replicas 1 \
    --max-replicas 2 \
    --output none
  echo "Created container app '$APP1_NAME'."
else
  echo "Container app '$APP1_NAME' already exists."
fi

if ! container_app_exists "$RESOURCE_GROUP" "$APP2_NAME"; then
  az containerapp create \
    --name "$APP2_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --environment "$ACA_ENVIRONMENT" \
    --image nginx \
    --target-port 80 \
    --ingress internal \
    --cpu 0.25 \
    --memory 0.5Gi \
    --min-replicas 1 \
    --max-replicas 2 \
    --output none
  echo "Created container app '$APP2_NAME'."
else
  echo "Container app '$APP2_NAME' already exists."
fi

# Retrieve FQDNs for backend apps (internal).  These FQDNs include the
# word 'internal' as part of the subdomain【580989064529322†L120-L134】.
APP1_FQDN=$(az containerapp show --name "$APP1_NAME" --resource-group "$RESOURCE_GROUP" --query properties.configuration.ingress.fqdn -o tsv)
APP2_FQDN=$(az containerapp show --name "$APP2_NAME" --resource-group "$RESOURCE_GROUP" --query properties.configuration.ingress.fqdn -o tsv)

# Look up the resource ID of the Container Apps environment.  This is
# required when rendering the YAML template for the Caddy reverse proxy.
ENV_ID=$(az containerapp env show \
  --resource-group "$RESOURCE_GROUP" \
  --name "$ACA_ENVIRONMENT" \
  --query id -o tsv)

# ----------------------------------------------------------------------------
# Step 3: Upload Caddyfile to Azure Files

echo "[3/4] Uploading Caddyfile to Azure Files share..."
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CADDYFILE_PATH="$SCRIPT_DIR/../caddy/Caddyfile"
if [ ! -f "$CADDYFILE_PATH" ]; then
  echo "ERROR: Caddyfile not found at $CADDYFILE_PATH" >&2
  exit 1
fi
az storage file upload \
  --account-name "$STORAGE_ACCOUNT_NAME" \
  --account-key "$SA_KEY" \
  --share-name "$FILE_SHARE_NAME" \
  --source "$CADDYFILE_PATH" \
  --path "Caddyfile" \
  --overwrite \
  --output none
echo "Uploaded Caddyfile to share $FILE_SHARE_NAME."

# ----------------------------------------------------------------------------
# Step 4: Deploy or update the Caddy reverse proxy

echo "[4/4] Deploying Caddy reverse proxy container app..."

TMP_DIR=$(mktemp -d)
CADDY_YAML_TEMPLATE="$SCRIPT_DIR/../caddy/caddy_app_template.yaml"
CADDY_YAML_RENDERED="$TMP_DIR/caddy.yaml"
if [ ! -f "$CADDY_YAML_TEMPLATE" ]; then
  echo "ERROR: YAML template not found at $CADDY_YAML_TEMPLATE" >&2
  exit 1
fi

# Render the YAML by replacing placeholders with actual values, including
# the public domain and Let's Encrypt email used by Caddy.
sed \
  -e "s/{{ENV_ID}}/$ENV_ID/g" \
  -e "s/{{LOCATION}}/$LOCATION/g" \
  -e "s/{{CADDY_APP_NAME}}/$CADDY_APP_NAME/g" \
  -e "s/{{APP1_FQDN}}/$APP1_FQDN/g" \
  -e "s/{{APP2_FQDN}}/$APP2_FQDN/g" \
  -e "s/{{STORAGE_NAME}}/$STORAGE_NAME/g" \
  -e "s/{{PUBLIC_DOMAIN}}/$PUBLIC_DOMAIN/g" \
  -e "s/{{LETS_ENCRYPT_EMAIL}}/$LETS_ENCRYPT_EMAIL/g" \
  "$CADDY_YAML_TEMPLATE" > "$CADDY_YAML_RENDERED"

# Create or update the Caddy app
if ! container_app_exists "$RESOURCE_GROUP" "$CADDY_APP_NAME"; then
  az containerapp create \
    --resource-group "$RESOURCE_GROUP" \
    --yaml "$CADDY_YAML_RENDERED" \
    --output none
  echo "Created Caddy container app '$CADDY_APP_NAME'."
else
  az containerapp update \
    --resource-group "$RESOURCE_GROUP" \
    --name "$CADDY_APP_NAME" \
    --yaml "$CADDY_YAML_RENDERED" \
    --output none
  echo "Updated Caddy container app '$CADDY_APP_NAME'."
fi

# Retrieve FQDN of Caddy app
CADDY_FQDN=$(az containerapp show --name "$CADDY_APP_NAME" --resource-group "$RESOURCE_GROUP" --query properties.configuration.ingress.fqdn -o tsv)

# Clean up temporary directory
rm -rf "$TMP_DIR"

# ----------------------------------------------------------------------------
# Output summary

echo "\nDeployment complete.  Access your services at the following URLs:"
echo "  Backend 1 (internal): $APP1_FQDN"
echo "  Backend 2 (internal): $APP2_FQDN"
echo "  Caddy reverse proxy (external): $CADDY_FQDN"
echo "\nTest the reverse proxy by navigating to:"
echo "  http://$CADDY_FQDN/app1"
echo "  http://$CADDY_FQDN/app2"