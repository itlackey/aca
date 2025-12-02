
# Platform Engineering Onboarding Lab: Azure Container Apps

Welcome to the ACA platform lab. This runbook walks you through:

1. Provisioning a sandbox Azure Container Apps environment using the **infra repo**.
2. Deploying two example apps (`web-hello` and `worker-service`).
3. Wiring secrets via Key Vault and exploring autoscaling.

You should complete this lab in your own personal resource group so you can
safely experiment.

---

## 1. Prerequisites

- Azure subscription with permission to create:
  - Resource groups
  - VNets and subnets
  - Log Analytics workspaces
  - Azure Container Apps environments
  - Key Vaults
  - Storage accounts
- Access to:
  - This **infra** repository
  - The `web-hello` app repository
  - The `worker-service` app repository
- Azure CLI installed locally **or** access to a CI pipeline (GitHub Actions or
  Azure DevOps) wired to this infra repo.
- Access to a container registry (e.g. Azure Container Registry).

---

## 2. Provision your sandbox environment

### Option A – Run locally

1. Clone the infra repo:

   ```bash
      git clone <infra-repo-url>
      cd aca-platform-infra
   ````

2. Copy the sample configuration and edit it:

   ```bash
   cd infra
   cp .env.example .env
   ```

   Set at minimum:

   - `SUBSCRIPTION_ID`
   - `RESOURCE_GROUP` (use a unique name, e.g. `rg-aca-sandbox-<yourname>`)
   - `LOCATION`
   - `KEYVAULT_NAME` and `STORAGE_ACCOUNT_NAME` (must be globally unique)
   - `ACA_ENVIRONMENT`
   - CIDR ranges for `VNET_ADDRESS_PREFIX` and `INFRA_SUBNET_PREFIX`
   - Optionally enable `CREATE_MANAGED_IDENTITY` and `ASSIGN_KV_ROLE`.

3. Log in and run the script:

   ```bash
   az login
   az account set --subscription "<your-subscription-id>"

   chmod +x create-resources.sh
   ./create-resources.sh
   ```

4. At the end, record the printed outputs:

   - Resource group name
   - ACA environment name
   - Key Vault URI
   - Storage account name
   - User-assigned identity resource ID (if created)

You’ll need these for the app deployments.

### Option B – Use CI (recommended for team workflows)

Depending on where your infra repo lives:

- **GitHub**: trigger the `infra-deploy` workflow (`Actions` → `infra-deploy`
  → `Run workflow`). Fill in any required inputs or select the correct
  environment.
- **Azure DevOps**: run the `DeployInfra` pipeline for your branch/environment.

Ask your platform lead which environment/variables to use.

---

## 3. Build and push the example app images

You’ll deploy two apps:

- `web-hello` – public HTTP app (Node/Express).
- `worker-service` – background worker (Python).

### 3.1. Web Hello

1. Clone the repo:

   ```bash
   git clone <web-hello-repo-url>
   cd web-hello
   ```

2. Build and push the image:

   ```bash
   REGISTRY=<your-registry>.azurecr.io
   IMAGE_TAG=latest

   docker build -t $REGISTRY/web-hello:$IMAGE_TAG .
   docker push $REGISTRY/web-hello:$IMAGE_TAG
   ```

3. Configure `.env`:

   ```bash
   cp .env.example .env
   ```

   Set:

   - `SUBSCRIPTION_ID`
   - `RESOURCE_GROUP` → **same RG** created by the infra script
   - `ACA_ENVIRONMENT` → environment name from infra output
   - `APP_NAME` → e.g. `web-hello-<yourname>`
   - `IMAGE` → `$REGISTRY/web-hello:$IMAGE_TAG`
   - Scaling settings (`MIN_REPLICAS`, `MAX_REPLICAS`, `HTTP_CONCURRENCY`).

   **Secrets:**

   - Add a connection string to your Key Vault as a secret (e.g.
     `db-connection-string`).
   - Put its URI in `DB_SECRET_URI` and set `IDENTITY_RESOURCE_ID` to the
     user-assigned identity resource ID printed by the infra script.

4. Deploy:

   ```bash
   ./scripts/deploy-containerapp.sh
   ```

5. Verify:

   - Use the ACA ingress URL (or your Caddy reverse proxy if configured) to
     hit `/` and `/health`.
   - Check logs in Azure Portal or via `az containerapp logs show`.

### 3.2. Worker Service

1. Clone the repo:

   ```bash
   git clone <worker-service-repo-url>
   cd worker-service
   ```

2. Build and push:

   ```bash
   REGISTRY=<your-registry>.azurecr.io
   IMAGE_TAG=latest

   docker build -t $REGISTRY/worker-service:$IMAGE_TAG .
   docker push $REGISTRY/worker-service:$IMAGE_TAG
   ```

3. Configure `.env`:

   ```bash
   cp .env.example .env
   ```

   Set:

   - `SUBSCRIPTION_ID`
   - `RESOURCE_GROUP`
   - `ACA_ENVIRONMENT`
   - `APP_NAME` → e.g. `worker-service-<yourname>`
   - `IMAGE` → `$REGISTRY/worker-service:$IMAGE_TAG`
   - `MESSAGE`, `INTERVAL_SECONDS`
   - `CPU`, `MEMORY`, `MIN_REPLICAS`, `MAX_REPLICAS`, `CPU_UTILIZATION`.

   Configure `DB_SECRET_URI`/`IDENTITY_RESOURCE_ID` or `DB_CONNECTION_STRING`
   the same way as for `web-hello`.

4. Deploy:

   ```bash
   ./scripts/deploy-containerapp.sh
   ```

5. Verify:

   - Use `az containerapp logs show` to confirm the worker is running and
     printing messages at the expected interval.
   - Watch how scaling behaves when you adjust `CPU_UTILIZATION` and apply an
     update.

---

## 4. Suggested exercises for new engineers

1. **Networking basics**

   - Locate the VNet and subnet created by the infra script.
   - Confirm the ACA environment is integrated with that subnet.

2. **Secrets and identities**

   - Create a new secret in Key Vault.
   - Wire it to `web-hello` and `worker-service` via the managed identity and
     verify they can read it.
   - Rotate the secret and redeploy.

3. **Autoscaling**

   - For `web-hello`, adjust `HTTP_CONCURRENCY` and send load (e.g. `hey` or
     `k6`) to trigger additional replicas.
   - For `worker-service`, experiment with CPU-based scaling thresholds.

4. **Reverse proxy (optional, if your Caddy setup is available)**

   - Add a new hostname + route in Caddy for your `web-hello` instance.
   - Verify TLS and routing work through Caddy into the internal ACA
     environment.

5. **Cleanup**

   - Use `infra/destroy-resources.sh` (or resource group deletion) to clean up
     your sandbox when finished.

---

## 5. When you’re done

- Confirm you can:

  - Read and modify the infra `.env` safely.
  - Deploy and update a Container App via script and/or pipelines.
  - Use Key Vault + managed identity for secrets.
  - Interpret basic ACA logs and scaling behaviour.
