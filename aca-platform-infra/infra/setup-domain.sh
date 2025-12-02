#!/usr/bin/env bash
#
# Setup custom domain for a container app
#
# Usage:
#   ./setup-domain.sh <app-name> <resource-group> <environment> <domain> [--bind-cert]
#
# Examples:
#   ./setup-domain.sh web-hello rg-aca aca-env app.example.com
#   ./setup-domain.sh web-hello rg-aca aca-env app.example.com --bind-cert

set -euo pipefail

if [[ $# -lt 4 ]]; then
  echo "Usage: ./setup-domain.sh <app-name> <resource-group> <environment> <domain> [--bind-cert]"
  exit 1
fi

APP_NAME=$1
RG=$2
ENV=$3
DOMAIN=$4
BIND_CERT=${5:-}

# Get app FQDN
FQDN=$(az containerapp show -n "$APP_NAME" -g "$RG" --query properties.configuration.ingress.fqdn -o tsv)
if [[ -z "$FQDN" ]]; then
  echo "Error: App '$APP_NAME' not found or has no ingress"
  exit 1
fi

# Get verification ID
VERIFICATION_ID=$(az containerapp env show -n "$ENV" -g "$RG" \
  --query properties.customDomainConfiguration.customDomainVerificationId -o tsv)

# Add hostname
echo "Adding hostname '$DOMAIN' to '$APP_NAME'..."
az containerapp hostname add --hostname "$DOMAIN" -n "$APP_NAME" -g "$RG" --output none 2>/dev/null || true

if [[ "$BIND_CERT" == "--bind-cert" ]]; then
  echo "Binding certificate..."
  az containerapp hostname bind --hostname "$DOMAIN" -n "$APP_NAME" -g "$RG" \
    --environment "$ENV" --validation-method CNAME
  echo ""
  echo "Done! https://$DOMAIN"
else
  SUBDOMAIN=$(echo "$DOMAIN" | cut -d. -f1)
  echo ""
  echo "Configure DNS:"
  echo "  CNAME: $SUBDOMAIN -> $FQDN"
  echo "  TXT:   asuid.$SUBDOMAIN -> $VERIFICATION_ID"
  echo ""
  echo "After DNS propagates, run:"
  echo "  ./setup-domain.sh $APP_NAME $RG $ENV $DOMAIN --bind-cert"
fi
