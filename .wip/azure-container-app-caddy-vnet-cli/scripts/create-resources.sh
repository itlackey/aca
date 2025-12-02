#!/usr/bin/env bash

##
# create-resources.sh
#
# This script provisions the shared infrastructure required for a "dual‑homed"
# Azure Container Apps deployment.  It builds on the original CLI example by
# adding support for **private endpoints** and **private DNS** so that
# storage access occurs only over a private network.  The high‑level tasks
# performed by this script are:
#
# 1. Create a resource group (if it doesn’t already exist).
# 2. Create or reuse a virtual network with two subnets:
#    • An infrastructure subnet (delegated to `Microsoft.App/environments`) for
#      the Container Apps environment.  The subnet must be at least a /23
#      address space as recommended【569073402552708†L589-L599】.
#    • A private‑endpoint subnet used to host Private Endpoints for Azure
#      services such as storage.  This subnet should be a small CIDR block
#      (for example /27) and must **not** be delegated.
# 3. Create an Azure Storage account and file share to hold diagnostics and
#    configuration files.  The storage account’s public network access is
#    disabled so that only private endpoints can reach it.
# 4. Create a Private DNS zone (`privatelink.file.core.windows.net`) and link
#    it to the virtual network.  This zone allows clients in the VNet to
#    resolve the storage account’s file service name to the private endpoint
#    address.  Microsoft lists this zone as the designated domain for the
#    Azure Files service【23463733748053†L545-L550】.
# 5. Create a Private Endpoint in the private‑endpoint subnet targeting the
#    storage account’s `file` service, and associate the DNS zone with the
#    endpoint.  After this step, DNS resolution and network access to the
#    storage account’s file service remain entirely on the private network.
# 6. Create a Container Apps environment integrated with the infrastructure
#    subnet.  The environment uses Azure Monitor for logging (no Log
#    Analytics workspace is required) and can be configured as internal only
#    via an environment variable.  The environment’s storage account is
#    passed so that logs are written to the same storage account.
# 7. Provision a Key Vault, Azure Container Registry and optional
#    user‑assigned managed identity.  These resources are identical to those
#    created by the original script and are included for completeness.
#
# This script is idempotent: running it multiple times will not recreate
# existing resources.  You can safely rerun the script to apply changes.

set -euo pipefail

# Load environment variables from the file specified by ENV_FILE or default
# to `.env` in the script directory.  Use `cp .env.example .env` to get
# started.  Variables defined in the .env file override defaults below.
ENV_FILE=${ENV_FILE:-"$(dirname "$0")/.env"}
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  set -o allexport
  source "$ENV_FILE"
  set +o allexport
else
  echo "Environment file '$ENV_FILE' not found. Copy .env.example to .env and update the values before running." >&2
  exit 1
fi

# Verify that required variables are set.  Extend this list as the
# infrastructure evolves.  For optional variables see the comments in
# `.env.example`.
required_vars=(
  RESOURCE_GROUP
  LOCATION
  VNET_NAME
  VNET_ADDRESS_PREFIX
  INFRA_SUBNET_NAME
  INFRA_SUBNET_PREFIX
  PE_SUBNET_NAME
  PE_SUBNET_PREFIX
  STORAGE_ACCOUNT_NAME
  ACA_ENVIRONMENT
  KEYVAULT_NAME
  ACR_NAME
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

# Optionally set the Azure subscription.  If SUBSCRIPTION_ID is not set
# the current default subscription configured via `az account` is used.
if [[ -n "${SUBSCRIPTION_ID:-}" ]]; then
  echo "Using subscription $SUBSCRIPTION_ID"
  az account set --subscription "$SUBSCRIPTION_ID"
fi

# Build a reusable array of tag arguments.  Tags are critical in
# production for cost allocation and governance.  They are passed to
# resource creation commands when any tag variables are provided.
TAGS_ARGS=()
if [[ -n "${TAG_ENVIRONMENT:-}" || -n "${TAG_OWNER:-}" || -n "${TAG_COST_CENTER:-}" ]]; then
  TAGS_ARGS=(--tags)
  [[ -n "${TAG_ENVIRONMENT:-}" ]] && TAGS_ARGS+=("environment=$TAG_ENVIRONMENT")
  [[ -n "${TAG_OWNER:-}" ]]        && TAGS_ARGS+=("owner=$TAG_OWNER")
  [[ -n "${TAG_COST_CENTER:-}" ]] && TAGS_ARGS+=("cost-center=$TAG_COST_CENTER")
fi

echo "\n==> Creating resource group '$RESOURCE_GROUP' in '$LOCATION'"
az group create \
  --name "$RESOURCE_GROUP" \
  --location "$LOCATION" \
  "${TAGS_ARGS[@]}" \
  --output none

echo "\n==> Creating virtual network '$VNET_NAME'"
if ! az network vnet show --resource-group "$RESOURCE_GROUP" --name "$VNET_NAME" --only-show-errors >/dev/null 2>&1; then
  az network vnet create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$VNET_NAME" \
    --location "$LOCATION" \
    --address-prefixes "$VNET_ADDRESS_PREFIX" \
    "${TAGS_ARGS[@]}" \
    --output none
else
  echo "VNet '$VNET_NAME' already exists. Skipping creation."
fi

# Create the infrastructure subnet (delegated) if it does not exist
echo "\n==> Creating delegated subnet '$INFRA_SUBNET_NAME'"
if ! az network vnet subnet show --resource-group "$RESOURCE_GROUP" --vnet-name "$VNET_NAME" --name "$INFRA_SUBNET_NAME" --only-show-errors >/dev/null 2>&1; then
  az network vnet subnet create \
    --resource-group "$RESOURCE_GROUP" \
    --vnet-name "$VNET_NAME" \
    --name "$INFRA_SUBNET_NAME" \
    --address-prefixes "$INFRA_SUBNET_PREFIX" \
    --delegations Microsoft.App/environments \
    --output none
else
  echo "Subnet '$INFRA_SUBNET_NAME' already exists."
fi

# Ensure the subnet is delegated to Container Apps
delegations=$(az network vnet subnet show \
  --resource-group "$RESOURCE_GROUP" \
  --vnet-name "$VNET_NAME" \
  --name "$INFRA_SUBNET_NAME" \
  --query "delegations[].serviceName" -o tsv || true)
if [[ "$delegations" != *"Microsoft.App/environments"* ]]; then
  echo "Delegating subnet '$INFRA_SUBNET_NAME' to Microsoft.App/environments..."
  az network vnet subnet update \
    --resource-group "$RESOURCE_GROUP" \
    --vnet-name "$VNET_NAME" \
    --name "$INFRA_SUBNET_NAME" \
    --delegations Microsoft.App/environments \
    --output none
fi

# Create the private-endpoint subnet if it does not exist
echo "\n==> Creating private endpoint subnet '$PE_SUBNET_NAME'"
if ! az network vnet subnet show --resource-group "$RESOURCE_GROUP" --vnet-name "$VNET_NAME" --name "$PE_SUBNET_NAME" --only-show-errors >/dev/null 2>&1; then
  az network vnet subnet create \
    --resource-group "$RESOURCE_GROUP" \
    --vnet-name "$VNET_NAME" \
    --name "$PE_SUBNET_NAME" \
    --address-prefixes "$PE_SUBNET_PREFIX" \
    --output none
else
  echo "Private endpoint subnet '$PE_SUBNET_NAME' already exists."
fi

# Retrieve the subnet IDs for later use
INFRA_SUBNET_ID=$(az network vnet subnet show --resource-group "$RESOURCE_GROUP" --vnet-name "$VNET_NAME" --name "$INFRA_SUBNET_NAME" --query id -o tsv)
PE_SUBNET_ID=$(az network vnet subnet show --resource-group "$RESOURCE_GROUP" --vnet-name "$VNET_NAME" --name "$PE_SUBNET_NAME" --query id -o tsv)

# ----------------------------------------------------------------------------
# Storage account and file share

echo "\n==> Creating storage account '$STORAGE_ACCOUNT_NAME'"
if ! az storage account show --resource-group "$RESOURCE_GROUP" --name "$STORAGE_ACCOUNT_NAME" --only-show-errors >/dev/null 2>&1; then
  az storage account create \
    --name "$STORAGE_ACCOUNT_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --sku Standard_LRS \
    --kind StorageV2 \
    --https-only true \
    --allow-blob-public-access false \
    "${TAGS_ARGS[@]}" \
    --output none
  echo "Created storage account '$STORAGE_ACCOUNT_NAME'."
else
  echo "Storage account '$STORAGE_ACCOUNT_NAME' already exists."
fi

# Retrieve storage account resource ID
STORAGE_ACCOUNT_ID=$(az storage account show --resource-group "$RESOURCE_GROUP" --name "$STORAGE_ACCOUNT_NAME" --query id -o tsv)

# Disable public network access on the storage account so that only private
# endpoints can access it
echo "\n==> Disabling public network access for storage account '$STORAGE_ACCOUNT_NAME'"
az storage account update \
  --resource-group "$RESOURCE_GROUP" \
  --name "$STORAGE_ACCOUNT_NAME" \
  --public-network-access Disabled \
  --output none

# Create a file share for configuration if FILE_SHARE_NAME is provided
if [[ -n "${FILE_SHARE_NAME:-}" ]]; then
  echo "\n==> Creating Azure Files share '$FILE_SHARE_NAME'"
  SA_KEY=$(az storage account keys list --resource-group "$RESOURCE_GROUP" --account-name "$STORAGE_ACCOUNT_NAME" --query '[0].value' -o tsv)
  if ! az storage share exists --account-name "$STORAGE_ACCOUNT_NAME" --account-key "$SA_KEY" --name "$FILE_SHARE_NAME" --query exists -o tsv | grep -q true; then
    az storage share create --account-name "$STORAGE_ACCOUNT_NAME" --account-key "$SA_KEY" --name "$FILE_SHARE_NAME" --output none
    echo "Created file share '$FILE_SHARE_NAME'."
  else
    echo "File share '$FILE_SHARE_NAME' already exists."
  fi
fi

# ----------------------------------------------------------------------------
# Private DNS zone and Private Endpoint

DNS_ZONE_NAME="privatelink.file.core.windows.net"
PE_NAME="${STORAGE_ACCOUNT_NAME}-file-pe"
PE_CONNECTION_NAME="${STORAGE_ACCOUNT_NAME}-file-conn"
DNS_ZONE_LINK_NAME="${VNET_NAME}-file-link"
DNS_ZONE_GROUP_NAME="${STORAGE_ACCOUNT_NAME}-file-zone-group"

echo "\n==> Creating Private DNS zone '$DNS_ZONE_NAME'"
if ! az network private-dns zone show --resource-group "$RESOURCE_GROUP" --name "$DNS_ZONE_NAME" --only-show-errors >/dev/null 2>&1; then
  az network private-dns zone create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$DNS_ZONE_NAME" \
    --output none
  echo "Created private DNS zone '$DNS_ZONE_NAME'."
else
  echo "Private DNS zone '$DNS_ZONE_NAME' already exists."
fi

echo "\n==> Linking DNS zone '$DNS_ZONE_NAME' to virtual network '$VNET_NAME'"
if ! az network private-dns link vnet show --resource-group "$RESOURCE_GROUP" --zone-name "$DNS_ZONE_NAME" --name "$DNS_ZONE_LINK_NAME" --only-show-errors >/dev/null 2>&1; then
  az network private-dns link vnet create \
    --resource-group "$RESOURCE_GROUP" \
    --zone-name "$DNS_ZONE_NAME" \
    --name "$DNS_ZONE_LINK_NAME" \
    --virtual-network "$VNET_NAME" \
    --registration-enabled false \
    --output none
  echo "Linked DNS zone '$DNS_ZONE_NAME' to VNet '$VNET_NAME'."
else
  echo "DNS zone '$DNS_ZONE_NAME' is already linked to VNet '$VNET_NAME'."
fi

echo "\n==> Creating private endpoint '$PE_NAME' for storage account '$STORAGE_ACCOUNT_NAME'"
if ! az network private-endpoint show --resource-group "$RESOURCE_GROUP" --name "$PE_NAME" --only-show-errors >/dev/null 2>&1; then
  az network private-endpoint create \
    --name "$PE_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --vnet-name "$VNET_NAME" \
    --subnet "$PE_SUBNET_NAME" \
    --private-connection-resource-id "$STORAGE_ACCOUNT_ID" \
    --group-id file \
    --connection-name "$PE_CONNECTION_NAME" \
    --output none
  echo "Created private endpoint '$PE_NAME'."
else
  echo "Private endpoint '$PE_NAME' already exists."
fi

echo "\n==> Creating DNS zone group '$DNS_ZONE_GROUP_NAME' for private endpoint"
if ! az network private-endpoint dns-zone-group show --resource-group "$RESOURCE_GROUP" --endpoint-name "$PE_NAME" --name "$DNS_ZONE_GROUP_NAME" --only-show-errors >/dev/null 2>&1; then
  az network private-endpoint dns-zone-group create \
    --resource-group "$RESOURCE_GROUP" \
    --endpoint-name "$PE_NAME" \
    --name "$DNS_ZONE_GROUP_NAME" \
    --private-dns-zone "$DNS_ZONE_NAME" \
    --zone-name "$DNS_ZONE_NAME" \
    --output none
  echo "Created DNS zone group '$DNS_ZONE_GROUP_NAME'."
else
  echo "DNS zone group '$DNS_ZONE_GROUP_NAME' already exists."
fi

# ----------------------------------------------------------------------------
# Container Apps environment

echo "\n==> Creating Container Apps environment '$ACA_ENVIRONMENT'"
# Build the argument list for environment creation.  We always specify the
# infrastructure subnet and the storage account for Azure Monitor diagnostics.
env_args=(
  --name "$ACA_ENVIRONMENT"
  --resource-group "$RESOURCE_GROUP"
  --location "$LOCATION"
  --infrastructure-subnet-resource-id "$INFRA_SUBNET_ID"
  --logs-destination azure-monitor
  --storage-account "$STORAGE_ACCOUNT_NAME"
  "${TAGS_ARGS[@]}"
)

# If INTERNAL_ONLY is true then create an internal environment without a public IP.
if [[ "${INTERNAL_ONLY:-false}" == "true" ]]; then
  env_args+=(--internal-only)
fi

if ! az containerapp env show --resource-group "$RESOURCE_GROUP" --name "$ACA_ENVIRONMENT" --only-show-errors >/dev/null 2>&1; then
  az containerapp env create "${env_args[@]}" --output none
  echo "Created Container Apps environment '$ACA_ENVIRONMENT'."
else
  echo "Container Apps environment '$ACA_ENVIRONMENT' already exists."
fi

# ----------------------------------------------------------------------------
# Key Vault

echo "\n==> Creating Key Vault '$KEYVAULT_NAME'"
if ! az keyvault show --name "$KEYVAULT_NAME" --resource-group "$RESOURCE_GROUP" --only-show-errors >/dev/null 2>&1; then
  az keyvault create \
    --name "$KEYVAULT_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --enable-rbac-authorization true \
    "${TAGS_ARGS[@]}" \
    --output none
  echo "Created Key Vault '$KEYVAULT_NAME'."
else
  echo "Key Vault '$KEYVAULT_NAME' already exists."
fi

# ----------------------------------------------------------------------------
# Azure Container Registry

echo "\n==> Ensuring Azure Container Registry '$ACR_NAME' exists"
ACR_SKU=${ACR_SKU:-Standard}
if ! az acr show --name "$ACR_NAME" --resource-group "$RESOURCE_GROUP" --only-show-errors >/dev/null 2>&1; then
  az acr create \
    --name "$ACR_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --sku "$ACR_SKU" \
    "${TAGS_ARGS[@]}" \
    --output none
  echo "Created ACR '$ACR_NAME'."
else
  echo "ACR '$ACR_NAME' already exists."
fi

# Capture ACR identifiers for role assignments
ACR_ID=$(az acr show --name "$ACR_NAME" --resource-group "$RESOURCE_GROUP" --query id -o tsv)
ACR_LOGIN_SERVER=$(az acr show --name "$ACR_NAME" --resource-group "$RESOURCE_GROUP" --query loginServer -o tsv)

# ----------------------------------------------------------------------------
# Optional: User-assigned managed identity and role assignments

if [[ "${CREATE_MANAGED_IDENTITY:-false}" == "true" ]]; then
  IDENTITY_NAME=${USER_ASSIGNED_IDENTITY_NAME:-"aca-uami"}
  echo "\n==> Creating user-assigned managed identity '$IDENTITY_NAME'"
  IDENTITY_RESOURCE_ID=$(az identity create \
    --name "$IDENTITY_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    "${TAGS_ARGS[@]}" \
    --query id -o tsv)
  IDENTITY_PRINCIPAL_ID=$(az identity show \
    --name "$IDENTITY_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --query principalId -o tsv)
  echo "   Managed identity principalId: $IDENTITY_PRINCIPAL_ID"

  # Assign Key Vault Secrets User role if requested.
  if [[ "${ASSIGN_KV_ROLE:-true}" == "true" ]]; then
    echo "\n==> Assigning 'Key Vault Secrets User' role on Key Vault to managed identity"
    KEYVAULT_ID=$(az keyvault show \
      --name "$KEYVAULT_NAME" \
      --resource-group "$RESOURCE_GROUP" \
      --query id -o tsv)
    az role assignment create \
      --role "Key Vault Secrets User" \
      --assignee "$IDENTITY_PRINCIPAL_ID" \
      --scope "$KEYVAULT_ID" \
      --only-show-errors || true
  fi

  # Assign AcrPull role on the ACR so container apps can pull images
  echo "\n==> Assigning 'AcrPull' role on ACR to managed identity"
  az role assignment create \
    --role "AcrPull" \
    --assignee "$IDENTITY_PRINCIPAL_ID" \
    --scope "$ACR_ID" \
    --only-show-errors || true
fi

echo "\nAll infrastructure resources have been created or updated successfully."
echo "Summary:"
printf "  Resource group:        %s\n" "$RESOURCE_GROUP"
printf "  Region:                %s\n" "$LOCATION"
printf "  Virtual network:       %s (%s)\n" "$VNET_NAME" "$VNET_ADDRESS_PREFIX"
printf "  Infrastructure subnet: %s (%s)\n" "$INFRA_SUBNET_NAME" "$INFRA_SUBNET_PREFIX"
printf "  Private endpoint subnet: %s (%s)\n" "$PE_SUBNET_NAME" "$PE_SUBNET_PREFIX"
printf "  Container Env:         %s\n" "$ACA_ENVIRONMENT"
printf "  Key vault:             %s\n" "$KEYVAULT_NAME"
printf "  Storage account:       %s\n" "$STORAGE_ACCOUNT_NAME"
printf "  ACR:                   %s\n" "$ACR_NAME"
printf "  ACR login server:      %s\n" "$ACR_LOGIN_SERVER"
if [[ "${CREATE_MANAGED_IDENTITY:-false}" == "true" ]]; then
  printf "  Managed identity:      %s\n" "${USER_ASSIGNED_IDENTITY_NAME:-aca-uami}"
fi

# Print useful identifiers for downstream scripts.
echo "\nUse these values when deploying your apps:"
echo "  ACA Environment name:       $ACA_ENVIRONMENT"
echo "  ACA Environment resource group: $RESOURCE_GROUP"
echo "  ACA Environment region:     $LOCATION"
echo "  Key Vault URI:              https://$KEYVAULT_NAME.vault.azure.net/"
echo "  Storage account:            $STORAGE_ACCOUNT_NAME"
echo "  Private DNS zone:           $DNS_ZONE_NAME"
echo "  ACR login server:           $ACR_LOGIN_SERVER"
if [[ "${CREATE_MANAGED_IDENTITY:-false}" == "true" ]]; then
  echo "  User-assigned identity resource ID: $IDENTITY_RESOURCE_ID"
fi