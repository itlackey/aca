# Platform Engineer Onboarding Lab

This runbook guides you through the end‑to‑end process of provisioning a
personal Azure Container Apps (ACA) platform using the `aca-platform-infra`
repository and then deploying sample applications.  It is tailored for
new engineers who need a safe sandbox to explore ACA and the supporting
Azure services.  Follow this document sequentially to learn how the
infrastructure pieces fit together and how to deploy applications via
both GitHub Actions and Azure DevOps.

## Prerequisites

Before you begin you will need:

1. An Azure subscription with permissions to create resource groups, VNets,
   Log Analytics workspaces, Key Vaults, Container Apps environments,
   Container Registries and managed identities.
2. The [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli)
   installed locally or a configured CI/CD service capable of running
   Azure CLI commands (GitHub Actions or Azure DevOps).
3. [GitHub CLI](https://cli.github.com/) installed if you plan to use
   the bootstrap script to configure secrets on your app repositories.
4. Access to the sample application repositories `web-hello` and
   `worker-service`.
5. A container registry (the infra script creates one automatically but
   you may also use an existing registry).

## Step 1: Provision your sandbox infrastructure

The `infra/create-resources.sh` script creates or updates the shared
infrastructure components.  You can run it locally or via a CI/CD
pipeline.  To run locally:

```bash
git clone <your-aca-platform-infra-repo>
cd aca-platform-infra/infra
cp .env.example .env
```

Edit `.env` and set values appropriate for your sandbox, such as
`RESOURCE_GROUP`, `LOCATION`, `KEYVAULT_NAME`, `STORAGE_ACCOUNT_NAME`,
`ACR_NAME` and network CIDR blocks.  Ensure the names for Key Vault,
storage and ACR are globally unique.  Optionally enable
`CREATE_MANAGED_IDENTITY` to provision a user‑assigned identity with
permissions to pull images and read secrets.

Then log in and run:

```bash
az login
az account set --subscription <your-subscription-id>
chmod +x create-resources.sh
./create-resources.sh
```

The script prints a summary of the resources created and values to
reference when deploying applications (ACA environment name, Key Vault
URI, ACR login server and identity resource ID).  Keep these values
handy or copy them into your environment files.

### Using CI/CD to provision

If you prefer not to run scripts locally, use the provided pipeline
definitions:

* **GitHub Actions** – `.github/workflows/infra-deploy.yml` runs
  `create-resources.sh` automatically when you push changes to the
  `infra/` folder.  Define the necessary secrets (e.g.
  `AZ_SUBSCRIPTION_ID`, `ACAPP_RG`, `AZURE_CREDENTIALS`, etc.) in your
  repository or GitHub environment.  The workflow assembles a `.env`
  file on the fly and executes the script.
* **Azure DevOps** – `azure-pipelines.yml` performs the same actions in
  Azure DevOps.  Configure an appropriate service connection and set
  variables either in the pipeline YAML or via variable groups.

## Step 2: Configure your app repositories

After the platform infrastructure is in place, each application
repository needs certain secrets to deploy into your ACA environment.
Run the helper script `tools/bootstrap-app-repo.sh` to populate these
secrets on your GitHub app repositories.  For example:

```bash
cd aca-platform-infra
export AZURE_CREDENTIALS_JSON='{"clientId":"...","clientSecret":"...","subscriptionId":"...","tenantId":"..."}'
./tools/bootstrap-app-repo.sh \
  --github-repo myorg/web-hello \
  --resource-group <your-RG> \
  --aca-env <your-env> \
  --acr-name <your-acr-name>
```

Repeat for each app repository (e.g. `worker-service`).  The script
stores secrets such as `AZ_SUBSCRIPTION_ID`, `ACAPP_RG`, `ACAPP_ENV`,
`ACR_NAME`, `ACR_LOGIN_SERVER` and (optionally) `AZURE_CREDENTIALS` on
the GitHub repository so your workflows can authenticate to Azure.

## Step 3: Build and push your application images

Clone the app repository you wish to deploy (e.g. `web-hello`).
Build the Docker image and push it to the ACR created in Step 1:

```bash
REGISTRY=<acr-login-server>  # e.g. acaregistrydemo1234.azurecr.io
APP_NAME=<app-name>          # e.g. web-hello
IMAGE_TAG=$(git rev-parse --short HEAD)

docker build -t $REGISTRY/$APP_NAME:$IMAGE_TAG .
docker push $REGISTRY/$APP_NAME:$IMAGE_TAG

echo "IMAGE=$REGISTRY/$APP_NAME:$IMAGE_TAG" >> .env
```

Note: your CI pipelines (see below) will perform these steps
automatically.

## Step 4: Deploy your application

Each app repository contains two deployment scripts:

* `scripts/deploy-containerapp.sh` – performs a full deployment from the
  YAML template (`aca/containerapp.yml`).  Use this when the app
  configuration changes (e.g. environment variables, scaling rules,
  ingress settings).  The script reads a `.env` file for required
  variables and creates or updates the container app using the Azure CLI.

* `scripts/deploy-image-only.sh` – updates only the container image on
  an existing container app.  Use this when you have built a new image
  but the configuration remains unchanged.  The script reads the same
  `.env` file and calls `az containerapp update --image` to roll out a
  new revision.  It fails if the app does not already exist.

### GitHub Actions workflows

Each app repository should include two workflows that correspond to the
deployment scripts:

* **`build-and-deploy-image.yml`** – triggered on changes to the source
  code or Dockerfile.  It logs into the ACR, builds and pushes the
  image, writes an `.env` file with the new `IMAGE` value and then
  runs `deploy-image-only.sh`.

* **`deploy-config.yml`** – triggered on changes to the app’s
  configuration files (`aca/containerapp.yml` or
  `scripts/deploy-containerapp.sh`).  It prepares an `.env` file and
  runs `deploy-containerapp.sh` to apply the updated configuration.

The workflows rely on secrets configured via the bootstrap script to
authenticate to Azure and access the ACR.

### Azure DevOps pipelines

For teams using Azure DevOps, include the following pipeline files in
each app repository:

* **`azure-pipelines-image.yml`** – runs on code changes, builds and
  pushes the image to ACR, updates an `.env` file and calls
  `deploy-image-only.sh`.  It uses the `AzureCLI@2` task to log in
  and run commands.

* **`azure-pipelines-config.yml`** – runs on changes to
  `containerapp.yml` or the deploy scripts.  It writes an `.env` file
  and calls `deploy-containerapp.sh` to apply the new configuration.

Define pipeline variables or variable groups corresponding to the `.env`
values (resource group, environment, ACR name, etc.) and configure a
service connection with sufficient permissions.  See the examples in
the infra repository’s `azure-pipelines.yml` for guidance.

## Step 5: Test scaling and secret management

Once your app is deployed, exercise ACA features:

1. **Scale** – Generate load (for HTTP apps) or CPU usage (for workers)
   and observe how the number of replicas changes.  Tweak the
   `MIN_REPLICAS`/`MAX_REPLICAS` and concurrency or CPU thresholds in
   `.env` and redeploy.
2. **Secrets** – Store a secret in Key Vault and reference it via
   `DB_SECRET_URI` in your app’s `.env`.  Ensure the managed identity
   has been granted the `Key Vault Secrets User` role.  Redeploy and
   verify the secret is projected into the container.
3. **Networking** – For internal‑only environments, access the app via
   your reverse proxy (e.g. Caddy) or private endpoint.  For public
   environments, test direct ingress.

## Step 6: Clean up

When you are finished with your sandbox, remove the resources to avoid
incurring charges.  You can delete the resource group via the Azure
Portal or run:

```bash
cd aca-platform-infra/infra
./destroy-resources.sh
```

Respond `y` when prompted.  All resources in the group will be deleted.

---

This runbook is intended to be a living document.  Update it as your
platform evolves and as you add new sample applications or deployment
scenarios.