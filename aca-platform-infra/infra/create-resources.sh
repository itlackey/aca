#!/usr/bin/env bash

# This script provisions the shared infrastructure for an Azure Container Apps
# deployment.  It is designed to be **production friendly** and easy to use
# as a training tool for new team members.
#
# The script creates or updates the following resources:
#   • Resource group
#   • Virtual network and delegated subnet for the ACA environment
#   • Log Analytics workspace for diagnostics
#   • Azure Storage account (general purpose v2) used for ACA diagnostics
#   • Azure Container Apps environment integrated with the delegated subnet
#   • Azure Key Vault with RBAC enabled
#   • Azure Container Registry (ACR) for storing container images
#   • Optional user‑assigned managed identity and role assignments for
#     Key Vault secrets read and ACR pull access
#
# All commands are idempotent.  Re‑running the script applies changes
# without recreating existing resources.  See the README for details.

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
  WORKSPACE_NAME
  ACA_ENVIRONMENT
  VNET_NAME
  VNET_ADDRESS_PREFIX
  INFRA_SUBNET_NAME
  INFRA_SUBNET_PREFIX
  KEYVAULT_NAME
  STORAGE_ACCOUNT_NAME
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
az network vnet create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$VNET_NAME" \
  --address-prefixes "$VNET_ADDRESS_PREFIX" \
  "${TAGS_ARGS[@]}" \
  --output none

echo "\n==> Creating delegated subnet '$INFRA_SUBNET_NAME'"
az network vnet subnet create \
  --resource-group "$RESOURCE_GROUP" \
  --vnet-name "$VNET_NAME" \
  --name "$INFRA_SUBNET_NAME" \
  --address-prefixes "$INFRA_SUBNET_PREFIX" \
  --delegations Microsoft.App/environments \
  --output none

# Retrieve the subnet resource ID.  This ID is required when creating
# the Container Apps environment as documented in the ACA networking guide.
INFRA_SUBNET_ID=$(az network vnet subnet show \
  --resource-group "$RESOURCE_GROUP" \
  --vnet-name "$VNET_NAME" \
  --name "$INFRA_SUBNET_NAME" \
  --query id -o tsv)

echo "\n==> Creating Log Analytics workspace '$WORKSPACE_NAME'"
az monitor log-analytics workspace create \
  --resource-group "$RESOURCE_GROUP" \
  --workspace-name "$WORKSPACE_NAME" \
  --location "$LOCATION" \
  "${TAGS_ARGS[@]}" \
  --output none

# Retrieve workspace identifiers used when creating the Container Apps environment.
WORKSPACE_ID=$(az monitor log-analytics workspace show \
  --resource-group "$RESOURCE_GROUP" \
  --workspace-name "$WORKSPACE_NAME" \
  --query customerId -o tsv)
WORKSPACE_KEY=$(az monitor log-analytics workspace get-shared-keys \
  --resource-group "$RESOURCE_GROUP" \
  --workspace-name "$WORKSPACE_NAME" \
  --query primarySharedKey -o tsv)

echo "\n==> Creating storage account '$STORAGE_ACCOUNT_NAME'"
az storage account create \
  --name "$STORAGE_ACCOUNT_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --location "$LOCATION" \
  --sku Standard_LRS \
  --kind StorageV2 \
  --allow-blob-public-access false \
  "${TAGS_ARGS[@]}" \
  --output none

echo "\n==> Creating Container Apps environment '$ACA_ENVIRONMENT'"
# Build the argument list for environment creation.  We always pass
# the storage account so that diagnostic logs can be routed there.
env_args=(
  --name "$ACA_ENVIRONMENT"
  --resource-group "$RESOURCE_GROUP"
  --location "$LOCATION"
  --infrastructure-subnet-resource-id "$INFRA_SUBNET_ID"
  --logs-workspace-id "$WORKSPACE_ID"
  --logs-workspace-key "$WORKSPACE_KEY"
  "${TAGS_ARGS[@]}"
)

# If INTERNAL_ONLY is true then create an internal environment without a public IP.
if [[ "${INTERNAL_ONLY:-false}" == "true" ]]; then
  env_args+=(--internal-only)
fi

az containerapp env create "${env_args[@]}" --output none

echo "\n==> Creating Key Vault '$KEYVAULT_NAME'"
az keyvault create \
  --name "$KEYVAULT_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --location "$LOCATION" \
  --enable-rbac-authorization true \
  "${TAGS_ARGS[@]}" \
  --output none

echo "\n==> Ensuring Azure Container Registry '$ACR_NAME' exists"
ACR_SKU=${ACR_SKU:-Standard}
if ! az acr show --name "$ACR_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
  az acr create \
    --name "$ACR_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --sku "$ACR_SKU" \
    "${TAGS_ARGS[@]}" \
    --only-show-errors
fi

# Capture ACR identifiers for printing and role assignments.
ACR_ID=$(az acr show \
  --name "$ACR_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query id -o tsv)
ACR_LOGIN_SERVER=$(az acr show \
  --name "$ACR_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query loginServer -o tsv)

# Optionally create a user-assigned managed identity and assign roles.
if [[ "${CREATE_MANAGED_IDENTITY:-false}" == "true" ]]; then
  IDENTITY_NAME=${USER_ASSIGNED_IDENTITY_NAME:-"aca-uami"}
  echo "\n==> Creating user-assigned managed identity '$IDENTITY_NAME'"
  # Create identity if not exists.  We can call az identity create repeatedly
  # because it is idempotent: if the identity exists, it is returned unchanged.
  IDENTITY_RESOURCE_ID=$(az identity create \
    --name "$IDENTITY_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    "${TAGS_ARGS[@]}" \
    --query id -o tsv)
  # Retrieve the principal ID separately.
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

  # Assign AcrPull role on the ACR so container apps can pull images when
  # using this identity.
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
printf "  Subnet:                %s (%s)\n" "$INFRA_SUBNET_NAME" "$INFRA_SUBNET_PREFIX"
printf "  Container Env:         %s\n" "$ACA_ENVIRONMENT"
printf "  Log workspace:         %s\n" "$WORKSPACE_NAME"
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
echo "  ACR login server:           $ACR_LOGIN_SERVER"
if [[ "${CREATE_MANAGED_IDENTITY:-false}" == "true" ]]; then
  echo "  User-assigned identity resource ID: $IDENTITY_RESOURCE_ID"
fi