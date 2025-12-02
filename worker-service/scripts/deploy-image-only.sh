#!/usr/bin/env bash

# Update only the container image of an existing worker-service
# Container App.  Use this script when you have built and pushed a new
# Docker image but have not changed any configuration (e.g. environment
# variables, scaling rules).  It reads the same `.env` file used by
# deploy-containerapp.sh and calls `az containerapp update --image`.

set -euo pipefail

# Determine repository root
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
: "${RESOURCE_GROUP:?RESOURCE_GROUP is required}"
: "${ACA_ENVIRONMENT:?ACA_ENVIRONMENT is required}"
: "${APP_NAME:?APP_NAME is required}"
: "${IMAGE:?IMAGE is required}"

# Optional subscription setting
if [[ -n "${SUBSCRIPTION_ID:-}" ]]; then
  az account set --subscription "$SUBSCRIPTION_ID"
fi

# Ensure the container app exists
set +e
az containerapp show \
  --name "$APP_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --only-show-errors &>/dev/null
exists=$?
set -e
if [[ $exists -ne 0 ]]; then
  echo "Error: container app '$APP_NAME' not found in resource group '$RESOURCE_GROUP'." >&2
  echo "Create it first using scripts/deploy-containerapp.sh." >&2
  exit 1
fi

# Perform the image update
echo "Updating image for worker-service '$APP_NAME' to $IMAGE"
az containerapp update \
  --name "$APP_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --image "$IMAGE" \
  --only-show-errors

echo "Image-only deploy complete for $APP_NAME."