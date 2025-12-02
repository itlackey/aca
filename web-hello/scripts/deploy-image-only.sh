#!/usr/bin/env bash

# Update the container image for an existing Azure Container App.  This
# script is a light‑weight alternative to deploy-containerapp.sh: it
# assumes the container app already exists and only updates the
# container image.  It reads the same `.env` file used by the full
# deploy script but ignores configuration settings such as CPU,
# memory, scaling rules and secrets.

set -euo pipefail

# Resolve repository paths
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(dirname "$SCRIPT_DIR")

# Load environment variables from .env
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
: "${RESOURCE_GROUP:?RESOURCE_GROUP is required}"
: "${ACA_ENVIRONMENT:?ACA_ENVIRONMENT is required}"
: "${APP_NAME:?APP_NAME is required}"
: "${IMAGE:?IMAGE is required}"

# Optionally set the subscription if specified
if [[ -n "${SUBSCRIPTION_ID:-}" ]]; then
  az account set --subscription "$SUBSCRIPTION_ID"
fi

# Check that the container app exists
set +e
az containerapp show \
  --name "$APP_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --only-show-errors &>/dev/null
exists=$?
set -e
if [[ $exists -ne 0 ]]; then
  echo "Error: Container app '$APP_NAME' does not exist in resource group '$RESOURCE_GROUP'." >&2
  echo "Run scripts/deploy-containerapp.sh first to create the app." >&2
  exit 1
fi

# Update the image.  This will create a new revision but retain all
# configuration settings defined previously.
echo "Updating container image for '$APP_NAME' to $IMAGE..."
az containerapp update \
  --name "$APP_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --image "$IMAGE" \
  --only-show-errors

echo "Image update complete for $APP_NAME."