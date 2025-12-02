#!/usr/bin/env bash

##
# destroy-resources.sh [env-file]
#
# Deletes the resource group and all resources.
#
# Usage:
#   ./destroy-resources.sh              # Uses .env in script directory
#   ./destroy-resources.sh .env.dev     # Uses specified env file

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Load environment file (argument or default to .env)
ENV_FILE="${1:-$SCRIPT_DIR/.env}"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "Error: Environment file '$ENV_FILE' not found."
  echo "Usage: ./destroy-resources.sh [env-file]"
  exit 1
fi

set -o allexport
# shellcheck disable=SC1090
source "$ENV_FILE"
set +o allexport

if [[ -z "${RESOURCE_GROUP:-}" ]]; then
  echo "Error: RESOURCE_GROUP is not set in $ENV_FILE" >&2
  exit 1
fi

if [[ -n "${SUBSCRIPTION_ID:-}" ]]; then
  az account set --subscription "$SUBSCRIPTION_ID"
fi

echo "Environment: $ENV_FILE"
echo "Resource group: $RESOURCE_GROUP"
read -r -p "Delete '$RESOURCE_GROUP' and ALL resources? (y/N) " answer

case "$answer" in
  [yY]*)
    echo "Deleting..."
    az group delete --name "$RESOURCE_GROUP" --yes --no-wait
    echo "Delete submitted. Check status: az group show -n $RESOURCE_GROUP"
    ;;
  *)
    echo "Aborted."
    ;;
esac
