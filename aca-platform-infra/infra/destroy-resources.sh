#!/usr/bin/env bash

# Helper script to delete the entire resource group created by the
# platform infrastructure.  Use this script during training or when
# cleaning up a demo environment.  It prompts for confirmation before
# deleting the group and all contained resources.

set -euo pipefail

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

if [[ -z "${RESOURCE_GROUP:-}" ]]; then
  echo "RESOURCE_GROUP is not set in $ENV_FILE" >&2
  exit 1
fi

if [[ -n "${SUBSCRIPTION_ID:-}" ]]; then
  az account set --subscription "$SUBSCRIPTION_ID"
fi

read -r -p "This will delete resource group '$RESOURCE_GROUP' and ALL resources in it. Are you sure? (y/N) " answer
case "$answer" in
  [yY][eE][sS]|[yY])
    echo "Deleting resource group '$RESOURCE_GROUP'..."
    az group delete \
      --name "$RESOURCE_GROUP" \
      --yes \
      --no-wait
    echo "Delete request submitted.  Use 'az group show --name $RESOURCE_GROUP' to check status."
    ;;
  *)
    echo "Aborted.  No resources were deleted."
    ;;
esac
