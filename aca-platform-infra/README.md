# Azure Container Apps Platform Infrastructure

Provisions shared infrastructure for Azure Container Apps. Apps deploy themselves.

## App Templates

| Template | Ingress | Use Case |
|----------|---------|----------|
| `public-app` | External (internet) | Public websites, external APIs, webhooks |
| `private-app` | Internal (VNet only) | Intranet apps, internal APIs, backend services |
| `worker-service` | None | Background jobs, queue processors, scheduled tasks |

## Quick Start

### 1. Deploy infrastructure

```bash
cd infra
cp .env.example .env
$EDITOR .env  # Set globally unique names

az login
./create-resources.sh
```

### 2. Deploy an app

```bash
# Copy template
cp -r templates/public-app ~/my-app
cd ~/my-app

# Edit containerapp.yml with your resource IDs
$EDITOR containerapp.yml

# Build and deploy
az acr build --registry <acr> --image my-app:v1 .
az containerapp create -g <rg> --yaml containerapp.yml
```

## Public vs Private Apps

The key difference is `ingress.external` in `containerapp.yml`:

```yaml
# PUBLIC - internet accessible
ingress:
  external: true   # Gets public FQDN: https://app.<id>.<region>.azurecontainerapps.io

# PRIVATE - VNet only
ingress:
  external: false  # Internal FQDN: http://app.internal.<id>.<region>.azurecontainerapps.io
```

**Private app access:**
- From within VNet: use internal FQDN directly
- From on-prem (VPN/ExpressRoute): configure DNS to point to environment's static IP
- Get static IP: `az containerapp env show -n <env> -g <rg> --query properties.staticIp`

## Repository Structure

```
aca-platform-infra/
├── infra/
│   ├── create-resources.sh   # Provisions infrastructure
│   ├── destroy-resources.sh  # Cleanup
│   ├── setup-domain.sh       # Custom domain helper
│   └── .env.example
├── templates/
│   ├── public-app/           # Internet accessible
│   ├── private-app/          # VNet only (10.x IP)
│   ├── worker-service/       # No HTTP (background jobs)
│   └── pipelines/
└── RUNBOOK.md
```

## CI/CD

Copy pipeline templates to your app repo:

| Pipeline | Triggers | Action |
|----------|----------|--------|
| `azure-pipelines-image.yml` | Code changes | Build image, update app |
| `azure-pipelines-config.yml` | YAML changes | Deploy full config |

## Custom Domains (public apps only)

```bash
./infra/setup-domain.sh <app> <rg> <env> app.example.com
# Configure DNS as shown, then:
./infra/setup-domain.sh <app> <rg> <env> app.example.com --bind-cert
```

## Cleanup

```bash
./infra/destroy-resources.sh
```
