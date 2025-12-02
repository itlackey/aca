# Web Hello Example App

This repository contains a small **Node.js/Express** application designed to
illustrate how to package and deploy an application to
[Azure Container Apps](https://learn.microsoft.com/azure/container-apps/).  It
is intended for onboarding and training purposes: new team members can use
this repo to practise building container images, pushing them to a registry
and deploying them to a Container Apps environment in their own test
resource group.

The app exposes an HTTP endpoint that responds with a JSON payload containing
a welcome message and the current timestamp.  It also reads a database
connection string from a secret, but doesn’t actually connect to a database.

## Repository structure

```
web-hello/
├── README.md                # This file
├── src/
│   └── index.js            # Express server
├── package.json            # Node dependencies and scripts
├── Dockerfile              # Build and runtime instructions for the container
├── aca/
│   └── containerapp.yml    # Template for the Container App definition
├── scripts/
│   └── deploy-containerapp.sh  # Deployment script using Azure CLI
└── .env.example            # Sample configuration for deployment
```

## Prerequisites

* An [Azure subscription](https://azure.microsoft.com/free/).
* [Docker](https://docs.docker.com/get-docker/) for building the container image.
* [Node.js](https://nodejs.org/) (optional if you want to run the app locally).
* [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) and the
  [Container Apps extension](https://learn.microsoft.com/azure/container-apps/azure-cli-extension).
* Access to a container registry (Azure Container Registry (ACR), GitHub
  Container Registry, Docker Hub, etc.) to push your built image.
* A Container Apps environment and supporting infrastructure.  See the
  companion `aca-platform-infra` repo for a reference implementation.

## Local development

1. Install dependencies:

   ```bash
   npm install
   ```

2. Run the app:

   ```bash
   node src/index.js
   ```

   It will listen on port 3000.  Navigate to `http://localhost:3000/` and you
   should see a JSON response.

## Building and pushing the image

The provided `Dockerfile` builds a production image with Node.js 18 on
Alpine.  Use your preferred registry and tag:

```bash
# Set these values appropriately
REGISTRY=<your-registry-name>.azurecr.io
IMAGE_TAG=latest

# Build the image
docker build -t $REGISTRY/web-hello:$IMAGE_TAG .

# Push the image to the registry
docker push $REGISTRY/web-hello:$IMAGE_TAG
```

If you’re using Azure Container Registry, log in first with
`az acr login --name <registry-name>`.

## Deployment

The `scripts/deploy-containerapp.sh` script uses the Azure CLI to create or
update the container app from the YAML template in `aca/containerapp.yml`.  It
expects a `.env` file in the repository root that defines the necessary
environment variables.  A sample file is provided as `.env.example`.

Steps to deploy:

1. Copy the sample environment file and edit it to match your settings:

   ```bash
   cp .env.example .env
   vim .env
   ```

   At a minimum you must set:
   * `RESOURCE_GROUP` – your personal or test resource group.
   * `ACA_ENVIRONMENT` – name of the Container Apps environment.
   * `APP_NAME` – the name for this app instance.
   * `IMAGE` – the fully qualified reference to your pushed image.

   If you wish to reference a secret from Azure Key Vault, set
   `DB_SECRET_URI` to the URI of the secret and `IDENTITY_RESOURCE_ID` to the
   resource ID of the user‑assigned managed identity that has access to that
   secret【209614643635596†L435-L505】.  Otherwise, set
   `DB_CONNECTION_STRING` directly in the `.env` file (not recommended for
   production).

2. Deploy the app:

   ```bash
   ./scripts/deploy-containerapp.sh
   ```

   The script will determine whether the container app already exists and
   create or update it accordingly.  It also injects secret values and
   substitutes placeholders in the YAML template.

### Image‑only deployments

Often you will make changes only to the application code without
modifying the ACA configuration.  In that case you can skip reapplying
the entire YAML template and simply roll out a new container image.  The
`scripts/deploy-image-only.sh` script updates the image on an existing
Container App without touching other settings.  It expects the same `.env`
file as the full deploy script and will fail if the app does not exist:

```bash
cp .env.example .env
vim .env  # set IMAGE to your new image tag
./scripts/deploy-image-only.sh
```

Use this script in your CI/CD pipeline to achieve faster deployments
when only the code (and container image) changes.

### Continuous deployment (CI/CD)

This repository includes example CI/CD configurations for **GitHub
Actions** and **Azure DevOps**.  These workflows demonstrate how to
automate image builds, pushes to Azure Container Registry and
deployments to Azure Container Apps.

* **GitHub Actions** – Two workflows are provided under
  `.github/workflows/`:
  - `build-and-deploy-image.yml` triggers on changes to source code or
    the Dockerfile.  It logs in to ACR, builds and pushes an image,
    writes an `.env` file with the new `IMAGE` value and then runs
    `deploy-image-only.sh` to update the app.
  - `deploy-config.yml` triggers on changes to `aca/containerapp.yml` or
    the deployment script.  It prepares a fresh `.env` and runs
    `deploy-containerapp.sh` to apply the updated configuration.
  These workflows rely on repository secrets (e.g. `AZURE_CREDENTIALS`,
  `ACAPP_RG`, `ACAPP_ENV`, `ACR_NAME`, `ACR_LOGIN_SERVER`) which are
  populated using the infra repo’s bootstrap script.

* **Azure DevOps** – Similarly, two pipeline definitions reside in the
  repository root:
  - `azure-pipelines-image.yml` builds and pushes the container image,
    writes an `.env` file and runs `deploy-image-only.sh`.
  - `azure-pipelines-config.yml` writes an `.env` and runs
    `deploy-containerapp.sh` on configuration changes.
  Configure a service connection with appropriate permissions and set
  variables either directly in the pipeline YAML or via variable groups.

## Files

### `src/index.js`

A minimal Express server.  It responds with a JSON object containing a
welcome message, the current timestamp and the `ENVIRONMENT` environment
variable (default `development`).  The server listens on the port defined in
the `PORT` environment variable or 3000 by default.

### `Dockerfile`

Builds a production image for the app:

* Uses the official Node 18 Alpine base image.
* Installs dependencies with `npm install --production`.
* Copies only the application source code.
* Exposes port 3000.
* Starts the app with `npm start`.

### `aca/containerapp.yml`

Template describing the Container App.  The deploy script fills in the
placeholders (`{{ENVIRONMENT_ID}}`, `{{IMAGE}}`, etc.) before passing it to
`az containerapp create` or `update`.  The template configures external
ingress on port 3000, defines a liveness probe, declares a secret
`db-connection-string`, and references that secret in an environment
variable.  The scale rule uses an HTTP concurrency trigger with a limit of
50 concurrent requests【847155983420235†L660-L675】.

### `scripts/deploy-containerapp.sh`

Deployment helper script.  See the comments in the script for details.  It
loads environment variables, resolves the Container Apps environment resource
ID, prepares the YAML file and calls the Azure CLI to create or update the
app.  It also constructs the `--secrets` argument based on whether you
provide a Key Vault secret URI or a plain secret value.

### `.env.example`

Sample configuration used by `deploy-containerapp.sh`.  Copy this file to
`.env` and fill in the appropriate values.  Do not commit your real secret
values to version control.

## Clean‑up

To remove the app from Azure, run:

```bash
az containerapp delete --name <APP_NAME> --resource-group <RESOURCE_GROUP>
```

## Next steps

* Experiment with different scaling rules (for CPU‑based scaling or KEDA
  triggers).
* Add additional environment variables and configuration sections in the YAML
  to suit your real application.
* Use managed identities and Key Vault references for all secrets
 【209614643635596†L435-L505】.
