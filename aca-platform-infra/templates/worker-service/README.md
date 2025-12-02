# worker-service

Python background worker template for Azure Container Apps. No HTTP ingress.

## Setup

1. Copy this template to your repo
2. Edit `containerapp.yml` with your Azure resource IDs
3. Build and deploy

## Deploy

```bash
# Build
az acr build --registry <acr> --image worker-service:v1 .

# Deploy
az containerapp create -g <rg> --yaml containerapp.yml

# Update image
az containerapp update -n worker-service -g <rg> --image <acr>.azurecr.io/worker-service:v2

# Update config
az containerapp update -n worker-service -g <rg> --yaml containerapp.yml
```

## Local Dev

```bash
python -m venv venv
source venv/bin/activate
pip install -r requirements.txt
python src/worker.py
```

## Customization

Edit `src/worker.py` to implement your worker logic:
- Queue processing
- Scheduled jobs
- Event handling
