# Platform Engineer Onboarding Lab

## Quick Reference

| Task | Command |
|------|---------|
| Build image | `az acr build --registry <acr> --image <app>:<tag> .` |
| Deploy app | `az containerapp create -g <rg> --yaml containerapp.yml` |
| Update image | `az containerapp update -n <app> -g <rg> --image <image>` |
| Update config | `az containerapp update -n <app> -g <rg> --yaml containerapp.yml` |
| Add domain | `./infra/setup-domain.sh <app> <rg> <env> <domain>` |
| View logs | `az containerapp logs show -n <app> -g <rg> --follow` |

## Step 1: Deploy Infrastructure

```bash
cd aca-platform-infra/infra
cp .env.example .env
$EDITOR .env  # Set unique names

az login
./create-resources.sh
```

**Save the output** - you'll need:

- ACR login server (e.g., `myacr.azurecr.io`)
- ACA environment ID
- Managed identity ID

## Step 2: Choose a Template

| Template | Use Case |
|----------|----------|
| `public-app` | Internet-facing websites, APIs |
| `private-app` | Intranet apps, internal services (VNet only) |
| `worker-service` | Background jobs, no HTTP |

## Step 3: Deploy Public App

```bash
cp -r templates/public-app ~/my-public-app
cd ~/my-public-app

# Edit containerapp.yml with your resource IDs
$EDITOR containerapp.yml

# Build and deploy
az acr build --registry <acr> --image public-app:v1 .
az containerapp create -g <rg> --yaml containerapp.yml

# Get public URL
az containerapp show -n public-app -g <rg> --query properties.configuration.ingress.fqdn -o tsv
```

## Step 4: Deploy Private App

```bash
cp -r templates/private-app ~/my-internal-app
cd ~/my-internal-app

$EDITOR containerapp.yml

az acr build --registry <acr> --image private-app:v1 .
az containerapp create -g <rg> --yaml containerapp.yml
```

**Access private app:**

```bash
# Get internal FQDN
az containerapp show -n private-app -g <rg> --query properties.configuration.ingress.fqdn -o tsv
# Returns: private-app.internal.<id>.<region>.azurecontainerapps.io

# Get environment's static IP (for on-prem DNS)
az containerapp env show -n <env> -g <rg> --query properties.staticIp -o tsv
```

## Step 5: Deploy Worker

```bash
cp -r templates/worker-service ~/my-worker
cd ~/my-worker

$EDITOR containerapp.yml

az acr build --registry <acr> --image worker-service:v1 .
az containerapp create -g <rg> --yaml containerapp.yml

# View logs (no URL - it's a background worker)
az containerapp logs show -n worker-service -g <rg> --follow
```

## Custom Domains (public apps only)

```bash
./infra/setup-domain.sh public-app <rg> <env> app.example.com
# Configure DNS as shown
./infra/setup-domain.sh public-app <rg> <env> app.example.com --bind-cert
```

## Key Vault Secrets

```bash
# Create secret
az keyvault secret set --vault-name <kv> --name db-password --value "secret"

# Add to containerapp.yml:
#   configuration.secrets:
#     - name: db-password
#       keyVaultUrl: https://<kv>.vault.azure.net/secrets/db-password
#       identity: <identity-id>
#   template.containers[].env:
#     - name: DB_PASSWORD
#       secretRef: db-password
```

## Cleanup

```bash
./infra/destroy-resources.sh
```
