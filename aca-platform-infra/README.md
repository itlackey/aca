# Azure Container Apps Platform Infrastructure

This repository contains a **production‑ready reference implementation**
for managing the shared infrastructure that underpins an
[Azure Container Apps](https://learn.microsoft.com/azure/container-apps/)
(ACA) deployment.  It is intended both as a real foundation for your
projects and as an onboarding lab for new engineers.

## What this repo provides

The `infra/create-resources.sh` script provisions or updates:

* **Resource group** – a single resource group per environment or per
  engineer for isolation and easy clean‑up.
* **Virtual network (VNet) and delegated subnet** – configured for
  Container Apps by delegating the subnet to
  `Microsoft.App/environments`【314694591115648†L657-L677】.  This allows the
  ACA environment and your apps to run inside your private network.
* **Log Analytics workspace** – used by ACA for diagnostics and log
  collection.
* **Azure Storage account** – general purpose v2 account used for
  diagnostic logs and available for your apps.
* **Azure Container Apps environment** – created with VNet
  integration and, optionally, as an internal‑only environment (no public
  IP) based on the `INTERNAL_ONLY` flag.
* **Azure Key Vault** – created with RBAC enabled.  You can store
  secrets here and reference them from your container apps via the
  `--secrets` parameter【209614643635596†L435-L505】.
* **Azure Container Registry (ACR)** – used to store container images for
  all of your ACA apps.  The script creates the registry if it doesn’t
  exist.
* **Optional user‑assigned managed identity** – when enabled, the script
  creates a user‑assigned identity and assigns it the built‑in
  **Key Vault Secrets User** role on the vault and **AcrPull** on the
  registry.  Your container apps can use this identity to pull images and
  read secrets securely without storing credentials in code.

All of these resources are tagged with the values provided in `.env` to
support cost allocation and governance.  Because the script is
idempotent, you can run it repeatedly as you adjust your configuration.

## Repository layout

```
aca-platform-infra/
├── infra/
│   ├── create-resources.sh    # Main provisioning script
│   ├── destroy-resources.sh   # Helper for cleaning up a training RG
│   └── .env.example           # Example configuration for the script
├── .github/
│   └── workflows/
│       └── infra-deploy.yml   # GitHub Actions workflow to run the script
├── azure-pipelines.yml        # Azure DevOps pipeline for the script
├── tools/
│   └── bootstrap-app-repo.sh  # Helper to wire GitHub app repos
├── RUNBOOK.md                # Onboarding lab instructions and runbook
└── README.md                  # This file
```

### `infra/create-resources.sh`

This script reads environment variables from an `.env` file and then
creates or updates the infrastructure.  The `.env.example` file
documents all available variables.  Key features:

* **Tagging** – optional tags (`environment`, `owner`, `cost-center`) are
  applied to all resources.
* **ACR creation** – ensures a registry exists and captures its login
  server and resource ID.  You can choose the SKU via `ACR_SKU`.
* **User‑assigned managed identity** – when `CREATE_MANAGED_IDENTITY=true`,
  the script creates a UAMI and grants it the `Key Vault Secrets User`
  role on the vault and `AcrPull` on the registry.  This identity is
  printed at the end for use in your app deployments.
* **Storage integration** – passes the storage account to
  `az containerapp env create` so that diagnostic logs can be stored there.

See the comments within the script for details and extend it as your
platform evolves.

### `infra/.env.example`

Provides a template for your `.env` file.  Copy it and update the values
to match your subscription, naming conventions and network ranges.  The
variables are grouped into sections:

1. **Subscription & resource group** – basic deployment target.
2. **Tagging** – optional tags for cost and ownership.
3. **Logging & environment** – workspace name, environment name and
   whether the environment is internal‑only.
4. **Networking** – VNet CIDR and delegated subnet CIDR.
5. **Key Vault & storage** – names for secrets and diagnostics.
6. **ACR** – registry name and SKU.
7. **Managed identity** – whether to create a UAMI and assign roles.

### `infra/destroy-resources.sh`

A simple clean‑up helper.  It loads `.env` and prompts you before
deleting the entire resource group.  Use it in training to tear down
personal sandboxes.

### `tools/bootstrap-app-repo.sh`

A Bash script for wiring up GitHub app repositories with the secrets
they need.  It accepts the GitHub repo name and relevant infra values and
uses the GitHub CLI (`gh`) to set repository secrets:

* Subscription ID, resource group and environment name
* ACR name and login server
* Optional service principal credentials (`AZURE_CREDENTIALS`)

See the script’s comments for usage.  Run it once per app repo after
provisioning the infrastructure.

### GitHub Actions workflow

The file `.github/workflows/infra-deploy.yml` defines a workflow that runs
`create-resources.sh` whenever changes are pushed to the `infra/` folder or
the workflow file itself.  It reads secrets from the repository or
environment to populate `.env` and calls the script.

### Azure DevOps pipeline

The root `azure-pipelines.yml` achieves the same as the GitHub Actions
workflow but for Azure DevOps.  It expects a service connection named
`aca-platform-service-connection` and variables defined via the pipeline
UI or variable groups.  The pipeline writes a `.env` file and then runs
`create-resources.sh` using the `AzureCLI@2` task.

## Usage

### 1. Prepare your `.env`

Clone this repository and copy the example configuration:

```bash
git clone <your-infra-repo-url>
cd aca-platform-infra/infra
cp .env.example .env
$EDITOR .env
```

Adjust the values to your environment (subscription ID, resource group,
network CIDRs, naming, etc.).  Pay special attention to globally unique
names for Key Vault, storage account and registry.

### 2. Run the script (local)

Log in with the Azure CLI (`az login`) and set the subscription if
necessary.  Then execute:

```bash
chmod +x create-resources.sh
./create-resources.sh
```

The script prints a summary of the resources created and values to use
when deploying apps:

* ACA environment name and resource group
* Region
* Key Vault URI and storage account name
* ACR login server
* User‑assigned identity resource ID (if created)

### 3. Use the GitHub or Azure DevOps workflow

Instead of running the script locally, you can let your CI/CD pipeline
manage the infrastructure.  Configure the appropriate secrets/variables in
your repository or pipeline environment (e.g. subscription ID, resource
group, Key Vault name, etc.).  The workflow will assemble a `.env` file
and invoke `create-resources.sh` automatically.

### 4. Wire your app repositories

After provisioning the platform, use the `tools/bootstrap-app-repo.sh`
script to set secrets in each app repository.  For example:

```bash
cd aca-platform-infra
export AZURE_CREDENTIALS_JSON='{"clientId":"...","clientSecret":"...","subscriptionId":"...","tenantId":"..."}'
./tools/bootstrap-app-repo.sh \
  --github-repo myorg/web-hello \
  --resource-group <your-RG> \
  --aca-env <your-env> \
  --acr-name <your-acr>
```

This populates secrets such as `AZ_SUBSCRIPTION_ID`, `ACAPP_RG`,
`ACAPP_ENV`, `ACR_NAME`, `ACR_LOGIN_SERVER` and (optionally) a service
principal credential into the GitHub repository.

### 5. Clean up (training)

When you no longer need your sandbox, run:

```bash
cd infra
./destroy-resources.sh
```

You will be prompted to confirm before the resource group is deleted.

## Onboarding lab

To walk through a complete end‑to‑end deployment using this
infrastructure and the sample applications (`web-hello` and
`worker-service`), see **RUNBOOK.md** in this repository.  The runbook
provides step‑by‑step instructions for provisioning your own sandbox,
bootstrapping application repositories, building and pushing images,
deploying apps via scripts and CI/CD, testing scaling and secrets, and
cleaning up resources when you are finished.  It is designed for new
team members learning Azure Container Apps and our platform practices.

## Relationship to app repositories

This repo defines the **platform**—networking, environment, vaults,
registry and identity.  Individual container apps live in their own
repositories (e.g. `web-hello`, `worker-service`).  Those repos contain:

* Application code and Dockerfile
* A `containerapp.yml` template describing the app
* Deployment scripts for full config (`deploy-containerapp.sh`) and
  image‑only updates (`deploy-image-only.sh`)
* CI pipelines (GitHub or Azure DevOps) to build/push images to the ACR
  and deploy them

Refer to the **runbook** in this repository (see `RUNBOOK.md` in the
release notes) for a step‑by‑step onboarding lab that ties the platform
infrastructure together with the sample apps.

## Extending for production

This baseline intentionally remains simple.  For a full production
deployment you may want to:

* Create separate VNets/subnets for ingress, private endpoints and data
  tiers.
* Add private endpoints to Key Vault and storage.
* Use multiple ACA environments (dev/test/prod) with different
  `.env` files.
* Wire this repo into your existing CI/CD system and treat it as the
  authoritative source for your platform infrastructure.
* Explore other features of ACA, such as revision management, scale rules,
  sidecars, Dapr, etc.

Because this repo uses plain Bash and the Azure CLI, it is easy to
migrate to more advanced tools such as Bicep or Terraform as your team
matures.  All of the concepts—networking, environment, logging, secrets
and registry—will carry forward.
