# web-hello

Node.js web app template for Azure Container Apps.

## Setup

1. Copy this template to your repo
2. Edit `containerapp.yml` with your Azure resource IDs
3. Build and deploy

## Deploy

```bash
# Build
az acr build --registry <acr> --image web-hello:v1 .

# Deploy
az containerapp create -g <rg> --yaml containerapp.yml

# Update image
az containerapp update -n web-hello -g <rg> --image <acr>.azurecr.io/web-hello:v2

# Update config
az containerapp update -n web-hello -g <rg> --yaml containerapp.yml
```

## Local Dev

```bash
npm install
npm start  # http://localhost:3000
```

## Endpoints

- `/` - Main endpoint
- `/health` - Health check
- `/ready` - Readiness check
