# Azure Container Apps Platform Infrastructure

Provisions shared infrastructure for Azure Container Apps. Apps deploy themselves.

## What this repo does

**Infra repo (this)** creates shared resources:
- Resource group, VNet, subnets
- Container Apps environment
- Azure Container Registry (ACR)
- Key Vault
- Managed identity (for ACR pull + Key Vault access)

**App repos** manage their own:
- `containerapp.yml` - app configuration
- `Dockerfile` - container image
- CI/CD pipelines

## Quick Start

### 1. Configure

```bash
cd infra
cp .env.example .env
$EDITOR .env  # Set globally unique names for storage, keyvault, acr
```

### 2. Deploy infrastructure

```bash
az login
./create-resources.sh           # uses .env
./create-resources.sh .env.dev  # or specify env file
```

Save the output - you'll need the resource IDs for your app's `containerapp.yml`.

### 3. Create an app

Copy a template to a new repo:

```bash
cp -r templates/web-hello ~/my-app
cd ~/my-app
```

Edit `containerapp.yml` with your resource IDs (from step 2), then:

```bash
# Build and push image
az acr build --registry <acr-name> --image my-app:v1 .

# Deploy
az containerapp create -g <resource-group> --yaml containerapp.yml
```

## Repository Structure

```
aca-platform-infra/
├── infra/
│   ├── create-resources.sh   # Provisions infrastructure
│   ├── destroy-resources.sh  # Cleanup
│   ├── setup-domain.sh       # Custom domain helper
│   └── .env.example
├── templates/
│   ├── web-hello/            # Web app with ingress
│   │   ├── containerapp.yml  # Copy and fill in your values
│   │   ├── Dockerfile
│   │   └── src/
│   ├── worker-service/       # Background worker (no ingress)
│   │   ├── containerapp.yml
│   │   ├── Dockerfile
│   │   └── src/
│   └── pipelines/            # CI/CD templates
│       ├── azure-pipelines-image.yml   # Build + push image
│       └── azure-pipelines-config.yml  # Deploy config changes
└── RUNBOOK.md
```

## App Deployment Flow

```
┌─────────────────┐     ┌─────────────────┐
│   Infra Repo    │     │    App Repo     │
├─────────────────┤     ├─────────────────┤
│ create-resources│────▶│ containerapp.yml│ (fill in resource IDs)
│ .sh             │     │ Dockerfile      │
│                 │     │ src/            │
│                 │     │ azure-pipelines │
└─────────────────┘     └────────┬────────┘
                                 │
                                 ▼
                        ┌─────────────────┐
                        │  az containerapp│
                        │  create --yaml  │
                        └─────────────────┘
```

**Code changes** → `az containerapp update --image`
**Config changes** → `az containerapp update --yaml`

## CI/CD

Each app repo has two pipelines:

| Pipeline | Triggers on | Does |
|----------|-------------|------|
| `azure-pipelines-image.yml` | `src/`, `Dockerfile` | Build image, update app |
| `azure-pipelines-config.yml` | `containerapp.yml` | Deploy full config |

## Custom Domains

Use the helper script:

```bash
# Step 1: Add domain and get DNS requirements
./infra/setup-domain.sh <app> <rg> <env> app.example.com

# Output shows:
#   CNAME: app -> <app-fqdn>
#   TXT:   asuid.app -> <verification-id>

# Step 2: Configure DNS records (manual step)

# Step 3: Bind certificate (after DNS propagates)
./infra/setup-domain.sh <app> <rg> <env> app.example.com --bind-cert
```

## Cleanup

```bash
cd infra
./destroy-resources.sh
```
