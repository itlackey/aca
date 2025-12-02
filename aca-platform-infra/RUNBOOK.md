# Platform Engineer Onboarding Lab

## Quick Reference

| Task | Command |
|------|---------|
| Build image | `az acr build --registry <acr> --image <app>:<tag> .` |
| Deploy app | `az containerapp create -g <rg> --yaml containerapp.yml` |
| Update image | `az containerapp update -n <app> -g <rg> --image <image>` |
| Update config | `az containerapp update -n <app> -g <rg> --yaml containerapp.yml` |
| Add domain | `./infra/setup-domain.sh <app> <rg> <env> <domain>` |
| Bind cert | `./infra/setup-domain.sh <app> <rg> <env> <domain> --bind-cert` |
| View logs | `az containerapp logs show -n <app> -g <rg> --follow` |

## Step 1: Deploy Infrastructure

```bash
cd aca-platform-infra/infra
cp .env.example .env
$EDITOR .env  # Set unique names for: STORAGE_ACCOUNT_NAME, KEYVAULT_NAME, ACR_NAME

az login
./create-resources.sh           # uses .env
./create-resources.sh .env.dev  # or specify env file
```

**Save the output** - copy these values for app configuration:
- `ACR login server` (e.g., `myacr.azurecr.io`)
- `ACA environment ID` (e.g., `/subscriptions/.../managedEnvironments/aca-env`)
- `Managed identity ID` (e.g., `/subscriptions/.../userAssignedIdentities/aca-uami`)

## Step 2: Create Your First App

```bash
# Copy template
cp -r templates/web-hello ~/web-hello
cd ~/web-hello

# Edit containerapp.yml - replace placeholders with your values:
# - <sub-id> → your subscription ID
# - <rg> → your resource group
# - <acr-name> → your ACR name
# - <env-name> → your ACA environment name
# - <identity-name> → your managed identity name
$EDITOR containerapp.yml
```

## Step 3: Build and Deploy

```bash
# Build image
az acr build --registry <acr-name> --image web-hello:v1 .

# Deploy
az containerapp create -g <rg> --yaml containerapp.yml
```

## Step 4: Verify

```bash
# Get URL
az containerapp show -n web-hello -g <rg> --query properties.configuration.ingress.fqdn -o tsv

# View logs
az containerapp logs show -n web-hello -g <rg> --follow
```

## Updating Apps

**Code change** (new image):
```bash
az acr build --registry <acr> --image web-hello:v2 .
az containerapp update -n web-hello -g <rg> --image <acr>.azurecr.io/web-hello:v2
```

**Config change** (scaling, env vars, secrets):
```bash
$EDITOR containerapp.yml
az containerapp update -n web-hello -g <rg> --yaml containerapp.yml
```

## CI/CD Setup

Copy pipeline templates to your app repo:
```bash
cp templates/pipelines/azure-pipelines-image.yml ~/web-hello/
cp templates/pipelines/azure-pipelines-config.yml ~/web-hello/
```

Edit variables in each pipeline file, then push to trigger deployments.

## Custom Domains

```bash
# Add domain and see DNS requirements
cd aca-platform-infra
./infra/setup-domain.sh web-hello <rg> <env> app.example.com

# Configure DNS (CNAME + TXT records shown in output)

# Bind certificate after DNS propagates
./infra/setup-domain.sh web-hello <rg> <env> app.example.com --bind-cert
```

## Key Vault Secrets

```bash
# Create secret
az keyvault secret set --vault-name <kv> --name db-password --value "secret123"

# Reference in containerapp.yml:
#   secrets:
#     - name: db-password
#       keyVaultUrl: https://<kv>.vault.azure.net/secrets/db-password
#       identity: <identity-resource-id>
#   template.containers[].env:
#     - name: DB_PASSWORD
#       secretRef: db-password
```

## Cleanup

```bash
cd aca-platform-infra/infra
./destroy-resources.sh           # uses .env
./destroy-resources.sh .env.dev  # or specify env file
```

