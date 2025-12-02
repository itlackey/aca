#!/usr/bin/env bash

# Bootstrap a GitHub app repository with the secrets required to
# deploy container images to an Azure Container Apps environment.  This
# script uses the GitHub CLI (`gh`) to set secrets on the specified
# repository.  It is intended to be run by platform engineers after
# provisioning the shared infrastructure with create-resources.sh.  See
# RUNBOOK.md for detailed instructions.

set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: bootstrap-app-repo.sh --github-repo <owner/repo> \
                             --resource-group <rg-name> \
                             --aca-env <env-name> \
                             --acr-name <acr-name> \
                             [--subscription-id <sub-id>]

Required arguments:
  --github-repo      GitHub repository in owner/repo format.  Must be a
                     repository you have permissions to manage secrets on.
  --resource-group   Resource group containing the ACA environment and ACR.
  --aca-env          Name of the Azure Container Apps environment.
  --acr-name         Name of the Azure Container Registry (ACR).  The script
                     will look up its login server automatically.

Optional arguments:
  --subscription-id  Azure subscription ID.  If omitted, the current
                     subscription from `az account show` is used.

Environment variables:
  AZURE_CREDENTIALS_JSON – JSON string representing a service principal
    credential used by GitHub Actions workflows.  If provided, this
    credential will be stored in the `AZURE_CREDENTIALS` secret on the
    target repository.  Otherwise, only the infrastructure secrets are set.

This script performs the following actions:
  1. Resolves the login server for the specified ACR.
  2. Assembles secrets containing the subscription ID, resource group,
     ACA environment name, ACR name and login server.
  3. Uses the GitHub CLI to set these secrets on the target repository.

Example:
  export AZURE_CREDENTIALS_JSON='{"clientId":"...","clientSecret":"...","subscriptionId":"...","tenantId":"..."}'
  ./bootstrap-app-repo.sh \
    --github-repo myorg/web-hello \
    --resource-group rg-aca-platform-demo \
    --aca-env aca-env-demo \
    --acr-name acaregistrydemo1234

USAGE
}

GITHUB_REPO=""
RESOURCE_GROUP=""
ACA_ENV=""
ACR_NAME=""
SUBSCRIPTION_ID=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --github-repo) GITHUB_REPO="$2"; shift 2;;
    --resource-group) RESOURCE_GROUP="$2"; shift 2;;
    --aca-env) ACA_ENV="$2"; shift 2;;
    --acr-name) ACR_NAME="$2"; shift 2;;
    --subscription-id) SUBSCRIPTION_ID="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown argument: $1" >&2; usage; exit 1;;
  esac
done

if [[ -z "$GITHUB_REPO" || -z "$RESOURCE_GROUP" || -z "$ACA_ENV" || -z "$ACR_NAME" ]]; then
  echo "Error: missing required arguments" >&2
  usage
  exit 1
fi

# Determine subscription ID if not provided
if [[ -z "$SUBSCRIPTION_ID" ]]; then
  SUBSCRIPTION_ID=$(az account show --query id -o tsv)
fi

echo "Using subscription ID: $SUBSCRIPTION_ID"

# Resolve the ACR login server
ACR_LOGIN_SERVER=$(az acr show \
  --name "$ACR_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query loginServer -o tsv)
if [[ -z "$ACR_LOGIN_SERVER" ]]; then
  echo "Failed to resolve ACR login server for registry '$ACR_NAME'" >&2
  exit 1
fi

echo "Setting secrets on GitHub repository: $GITHUB_REPO"

# Create secrets on the GitHub repository
gh secret set AZ_SUBSCRIPTION_ID --repo "$GITHUB_REPO" --body "$SUBSCRIPTION_ID"
gh secret set ACAPP_RG          --repo "$GITHUB_REPO" --body "$RESOURCE_GROUP"
gh secret set ACAPP_ENV         --repo "$GITHUB_REPO" --body "$ACA_ENV"
gh secret set ACR_NAME          --repo "$GITHUB_REPO" --body "$ACR_NAME"
gh secret set ACR_LOGIN_SERVER  --repo "$GITHUB_REPO" --body "$ACR_LOGIN_SERVER"

if [[ -n "${AZURE_CREDENTIALS_JSON:-}" ]]; then
  gh secret set AZURE_CREDENTIALS --repo "$GITHUB_REPO" --body "$AZURE_CREDENTIALS_JSON"
else
  echo "Warning: AZURE_CREDENTIALS_JSON not set.  The AZURE_CREDENTIALS secret will not be populated."
fi

echo "Secrets configured successfully for $GITHUB_REPO"