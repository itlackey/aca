# Worker Service Example App

This repository contains a simple **Python** background service that runs
continuously inside an Azure Container App.  It is designed to mimic a
long‑running worker job (for example, polling a message queue or performing
scheduled tasks) and demonstrates how to configure a non‑HTTP container
application in Azure Container Apps.

The service reads a message and polling interval from environment variables
and writes a timestamped entry to standard output every interval seconds.
It also reads a database connection string from a secret to illustrate
secret management.

## Repository structure

```
worker-service/
├── README.md                # This file
├── app/
│   ├── main.py              # Worker logic
│   └── requirements.txt     # Python dependencies (none in this example)
├── Dockerfile              # Build instructions for the container
├── aca/
│   └── containerapp.yml    # Template for the Container App definition
├── scripts/
│   └── deploy-containerapp.sh  # Deployment script using Azure CLI
└── .env.example            # Sample environment variables for deployment
```

## Prerequisites

Same as for the `web-hello` app: Docker, Python, Azure CLI with the
Container Apps extension, and access to a container registry.  You also
need a Container Apps environment.

## Local development

To run the worker locally:

```bash
pip install -r app/requirements.txt
python app/main.py
```

Set environment variables `MESSAGE`, `INTERVAL_SECONDS` and optionally
`ENVIRONMENT` and `DB_CONNECTION_STRING` to observe different behaviours.

## Building and pushing the image

```bash
REGISTRY=<your-registry>.azurecr.io
IMAGE_TAG=latest
docker build -t $REGISTRY/worker-service:$IMAGE_TAG .
docker push $REGISTRY/worker-service:$IMAGE_TAG
```

## Deployment

Deployment is similar to the web app.  Copy `.env.example` to `.env`, fill
in the values (resource group, environment name, app name, image, etc.) and
run the deploy script:

```bash
cp .env.example .env
vim .env  # update values
./scripts/deploy-containerapp.sh
```

This worker does **not** expose an HTTP endpoint and therefore does not
define an ingress.  The worker will start when deployed and will scale
based on CPU utilization.  You can configure different scale rules in the
YAML template (see `scale` section).

### Image‑only deployments

When you modify only the worker’s code (not its configuration), you can
push a new image and update the existing container app without
reapplying the full YAML.  Use the `scripts/deploy-image-only.sh` script
for this purpose.  It reads the same `.env` file and calls
`az containerapp update --image`:

```bash
cp .env.example .env
vim .env  # set IMAGE to your new image tag
./scripts/deploy-image-only.sh
```

This approach creates a new revision of the worker app with the new
image while retaining environment variables, scaling rules and secrets.

### Continuous deployment (CI/CD)

As with the web app, this repository includes example workflows and
pipelines that automate the build and deployment process:

* **GitHub Actions**:
  - `build-and-deploy-image.yml` builds the Docker image when source
    files or the Dockerfile change, pushes it to ACR and runs
    `deploy-image-only.sh`.
  - `deploy-config.yml` runs when the YAML template or deployment
    scripts change and applies the new configuration via
    `deploy-containerapp.sh`.
  These workflows depend on repository secrets configured via the infra
  bootstrap script.

* **Azure DevOps**:
  - `azure-pipelines-image.yml` builds and pushes the container image,
    writes an `.env` file and runs `deploy-image-only.sh`.
  - `azure-pipelines-config.yml` writes an `.env` file and runs
    `deploy-containerapp.sh` when configuration files are modified.
  Use an Azure service connection and pipeline variables to supply the
  necessary values.

## Files

### `app/main.py`

Main entrypoint for the worker.  It reads environment variables and logs a
message at a configurable interval.  In a real application you could
replace the body of the loop with calls to Azure Service Bus, Storage
Queues, event processing, etc.

### `Dockerfile`

Creates a Python 3.11 image using the `python:3.11-slim` base image.  It
installs dependencies from `requirements.txt` and then copies the
application code.  The default command runs `python app/main.py`.

### `aca/containerapp.yml`

Template describing a background container app.  The deploy script
substitutes placeholders (e.g. `{{ENVIRONMENT_ID}}`, `{{IMAGE}}`)
before deploying.  Since the worker has no HTTP interface, it omits the
ingress configuration entirely.  It defines a secret for the database
connection string and environment variables to control the message and
interval.  The app scales between 0 and 3 replicas based on CPU
utilization.

### `scripts/deploy-containerapp.sh`

Deployment helper similar to the web app script.  It checks whether the
container app exists and calls either `az containerapp create` or
`az containerapp update` with the prepared YAML file and secrets.

### `.env.example`

Sample configuration file for deployment.  Copy to `.env` and populate the
values appropriate for your environment and registry.  It includes
defaults for CPU, memory, replicas and scaling.

## Clean‑up

To remove the worker from Azure, run:

```bash
az containerapp delete --name <APP_NAME> --resource-group <RESOURCE_GROUP>
```

## Next steps

* Modify `main.py` to perform real work (consume messages, call APIs, etc.).
* Adjust the scaling rules in the YAML to use event‑driven triggers (e.g.
  Azure Service Bus, Storage queue) when ready.
* Use Azure Key Vault for all secrets, following the guidance in
  the Container Apps documentation【209614643635596†L435-L505】.
