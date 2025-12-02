# Azure Container Apps environment with Caddy reverse proxy (CLI Edition)

This repository shows how to build an Azure Container Apps solution using **only
the Azure CLI and Bash scripts**.  It provisions a dual‑homed Container Apps
environment inside a virtual network, creates two internal web services,
configures a Caddy reverse proxy to route external traffic to those services,
and mounts a Caddy configuration file from an Azure Files share.  The goal is
to demonstrate how you can achieve the same result as the Bicep example using
imperative commands.

## Why this example?

Azure Container Apps lets you run microservices without managing Kubernetes.
When you need more control over networking and ingress, you can integrate a
Container Apps environment with a custom virtual network.  Microsoft
recommendations require the subnet used for Container Apps to be at least a
/23 address range and delegated to `Microsoft.App/environments`【569073402552708†L589-L599】
【569073402552708†L623-L627】.  You also need a Log Analytics workspace for container
logging, and the CLI accepts the workspace ID and key when creating the
environment【569073402552708†L654-L680】.  To mount a Caddyfile from Azure Files you
must first configure the environment storage using `az containerapp env storage
set`【885288297229663†L620-L627】 and then update the container app via YAML
specification【885288297229663†L732-L736】.

This repository wraps all of those steps into easily understandable Bash
scripts while referencing the official documentation.  Use it as a starting
point for your own platform engineering automation.

## Features

- **Virtual network integration** – creates a VNet with two subnets.  The
  infrastructure subnet is at least a /23 and delegated to
  `Microsoft.App/environments`【569073402552708†L589-L599】【569073402552708†L623-L627】.  A second
  private‑endpoint subnet hosts Private Endpoints for Azure Files, enabling
  dual‑homed access to storage over private IP addresses.
- **Dual‑homed environment** – the Container Apps environment can operate in
  private or dual‑homed mode.  Set `INTERNAL_ONLY=true` in your `.env` file
  to make the environment private (no public IP).  Set it to `false` to
  allow container apps with external ingress to receive public traffic
  while internal apps remain private.
- **Azure Monitor integration** – leverages Azure Monitor by specifying
  `--logs-destination azure-monitor` and `--storage-account` on
  `az containerapp env create`.  This sends diagnostic logs to a storage
  account rather than requiring a Log Analytics workspace.
- **Azure Files mount** – provisions a storage account and file share, disables
  public network access, creates a Private Endpoint targeting the `file`
  service, and configures a Private DNS zone (`privatelink.file.core.windows.net`)
  linked to the VNet.  This ensures container apps mount the share over
  private IPs only【23463733748053†L545-L550】.  The share is registered with the
  environment using `az containerapp env storage set`
  (supports `ReadOnly` or `ReadWrite` modes)【885288297229663†L620-L627】.
- **Internal services** – two sample container apps (`app1` and `app2`) run
  lightweight NGINX images.  They accept only internal ingress and use the
  smallest supported CPU/memory combination (0.25 vCPU and 0.5 GiB RAM) as
  documented in the CLI reference【344094499861713†L3038-L3041】【344094499861713†L3180-L3183】.
- **Caddy reverse proxy** – a Caddy app listens on port 80 and routes
  `/app1` and `/app2` paths to the internal services using environment
  variables for their fully qualified domain names.  The Caddyfile is loaded
  from the Azure Files share.
- **End‑to‑end automation** – a `create-resources.sh` script builds the
  network, storage, Private DNS zone, Private Endpoint, environment,
  Key Vault and ACR, and a `deploy.sh` script creates the apps and
  Caddy reverse proxy.

## Repository structure

| Path | Purpose |
|---|---|
| `scripts/deploy.sh` | Main orchestrator script that creates all resources in the correct order and outputs service URLs. |
| `scripts/create-resources.sh` | New script that provisions the shared infrastructure (resource group, VNet with two subnets, storage account, private DNS zone, private endpoint, Container Apps environment, Key Vault, ACR and optional managed identity). |
| `caddy/Caddyfile` | Caddy configuration used by the reverse proxy.  It maps `/app1` and `/app2` to the internal services. |
| `caddy/caddy_app_template.yaml` | A YAML template used by the script to deploy or update the Caddy container app.  It contains placeholders for the environment ID, backend FQDNs and storage name. |
| `assets/architecture.png` | Conceptual architecture diagram of the solution. |

## Prerequisites

1. **Azure CLI** – Install the Azure CLI and ensure you’re authenticated.  You
   must also install the Container Apps extension: `az extension add --name
   containerapp`.
2. **Bash shell** – The scripts are written for a POSIX‐compliant shell.
3. **Subscription & permissions** – You need permissions to create resource
   groups, virtual networks, Container Apps environments, storage accounts,
   Private DNS zones, Private Endpoints and supporting services such as Key
   Vault and Azure Container Registry.

## Deployment

### 1. Provision shared infrastructure

The `create-resources.sh` script provisions the base infrastructure
including the dual‑homed virtual network, private DNS and storage
endpoint.  Copy `.env.example` to `.env`, adjust the values for your
subscription and naming conventions, then run:

```bash
# prepare environment variables
cp scripts/.env.example scripts/.env
# customise scripts/.env in your editor

# make the script executable
chmod +x scripts/create-resources.sh

# run the provisioning
scripts/create-resources.sh
```

The script performs these tasks:

1. **Resource group** – Creates the resource group if it doesn’t exist.
2. **VNet and subnets** – Creates a virtual network with two subnets:
   - **Infrastructure subnet**: a /23 address space delegated to
     `Microsoft.App/environments`【569073402552708†L589-L599】【569073402552708†L623-L627】.
   - **Private Endpoint subnet**: a small subnet for hosting the storage
     private endpoint.  It is not delegated.
3. **Storage account** – Creates a storage account, disables public network
   access and optionally creates a file share.  A Private Endpoint for the
   `file` service is created in the dedicated subnet.  A Private DNS zone
   (`privatelink.file.core.windows.net`) is created and linked to the VNet
   so that Azure Files is reachable over private IPs【23463733748053†L545-L550】.
4. **Container Apps environment** – Creates or reuses an environment using
   Azure Monitor for logging and integrates it with the infrastructure
   subnet.  You can make the environment public by setting
   `INTERNAL_ONLY=false` in `.env`.
5. **Key Vault, ACR and identity** – Ensures these supporting services
   exist and optionally creates a user‑assigned managed identity with
   appropriate role assignments.

### 2. Deploy the apps and Caddy reverse proxy

After provisioning the infrastructure, use the `deploy.sh` script to
deploy the internal services and the Caddy reverse proxy.  Edit the
variables at the top of `deploy.sh` to match the names used in
`.env` and run:

```bash
chmod +x scripts/deploy.sh
scripts/deploy.sh
```

This script will:

1. Register the Azure Files share with the environment (`az containerapp env
   storage set`【885288297229663†L620-L627】).
2. Deploy the two internal services (`app1` and `app2`) using `az containerapp
   create` and the smallest valid CPU/memory settings【344094499861713†L3038-L3041】.
3. Upload the `Caddyfile` to the share.
4. Generate a YAML specification for the Caddy app using the provided
   template and deploy or update the reverse proxy via `az containerapp
   create --yaml`【885288297229663†L732-L736】.
5. Print the internal FQDNs of the backend services and the external FQDN of
   the Caddy reverse proxy.  Internal FQDNs include the word `internal`
   in the subdomain【580989064529322†L120-L134】.

### Choosing internal‑only or dual‑homed ingress

The Container Apps environment can be configured for internal only
ingress by setting `INTERNAL_ONLY=true` in your `.env` file.  In this
mode, the environment does not expose a public IP and only container apps
with `--ingress external` will be reachable externally through Azure’s
ingress infrastructure.  To allow both private and public ingress (dual
homed), set `INTERNAL_ONLY=false` and configure your Caddy app with
external ingress.

```bash
# make the script executable
chmod +x scripts/deploy.sh

# run the deployment (use your own resource group / names / location as desired)
scripts/deploy.sh
```

The script performs the following tasks:

1. **Resource group** – Creates the resource group if it doesn’t exist.
2. **VNet and subnet** – Creates a /16 VNet and a /23 subnet and delegates
   it to Container Apps【569073402552708†L589-L599】【569073402552708†L623-L627】.
3. **Log Analytics workspace** – Creates or reuses a workspace and
   retrieves its ID and shared key【911427446337382†L915-L919】【911427446337382†L1635-L1645】.
4. **Container Apps environment** – Creates an internal environment
   integrated with the subnet using `az containerapp env create`【569073402552708†L654-L680】.
5. **Storage and Azure Files share** – Creates a storage account and file
   share, then registers it with the environment via `az containerapp env
   storage set`【885288297229663†L620-L627】.
6. **Backend apps** – Deploys two internal apps (`app1`, `app2`) using
   `az containerapp create`, specifying CPU and memory within the
   allowed ranges【344094499861713†L3038-L3041】【344094499861713†L3180-L3183】.
7. **Caddy upload** – Uploads the `Caddyfile` to the Azure Files share.
8. **Caddy deployment** – Generates a YAML definition using the
   `caddy_app_template.yaml` file, substituting the environment ID,
   backend FQDNs and storage name.  The YAML is passed to `az
   containerapp create --yaml` (or `az containerapp update --yaml`) to
   deploy the Caddy app【885288297229663†L732-L736】.
9. **Outputs** – Prints the internal FQDNs of the backend services and the
   external FQDN of the Caddy reverse proxy.  Internal FQDNs include the
   word `internal` in the subdomain【580989064529322†L120-L134】.

### Running individual steps

If you prefer a more granular approach, the script is modular.  Each
section of the script is demarcated and can be extracted into a separate
script (e.g., network setup, environment creation, app deployment).  The
provided helper functions check for existing resources and skip steps
accordingly, which allows you to re‑run the script safely.

### Cleaning up

To remove all resources created by this example, delete the resource
group:

```bash
az group delete --name <your-resource-group> --yes --no-wait
```

Deleting the resource group removes the environment, virtual network,
storage, log analytics workspace and container apps.

## Architecture diagram

The diagram below illustrates the solution.  A custom VNet contains the
Container Apps environment (internal only).  Two internal services (`app1`
and `app2`) run inside the environment.  A Caddy reverse proxy is exposed
externally and proxies traffic to the internal services based on the URL
path.  An Azure storage account hosts the `Caddyfile`, which is mounted
into the Caddy container via an Azure Files share.  Diagnostic logs are
written to Azure Monitor via the configured storage account.

![Architecture diagram]({{file:file-7KqYxQ6mhNziRQKVA5k7cs}})

## Notes

1. The CLI currently requires YAML to mount volumes in a container app.
   The script uses a template file to build this YAML and deploy the
   Caddy reverse proxy.  See the [Use storage mounts in Azure Container
   Apps](https://learn.microsoft.com/en-us/azure/container-apps/storage-mounts)
   documentation for more details.
2. The consumption workload profile is implicitly used by the environment
   creation command.  If you need to specify dedicated workloads or
   different SKUs, adjust the `az containerapp env create` call accordingly.
3. CPU and memory values are passed as decimals (e.g., `0.25` vCPU).  The
   CLI’s parameter schema expects integers, so you may see linter
   warnings, but these values are accepted by the service and are within
   the allowed ranges【344094499861713†L3038-L3041】【344094499861713†L3180-L3183】.

## Further reading

- [Integrate a virtual network with an Azure Container Apps environment](https://learn.microsoft.com/en-us/azure/container-apps/vnet-custom) – detailed guidance on VNet integration and subnet delegation.
- [Use storage mounts in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/storage-mounts) – explains environment storage, volume mounts and updating apps via YAML【885288297229663†L620-L627】【885288297229663†L732-L736】.
- [Azure CLI reference for `az containerapp`](https://learn.microsoft.com/en-us/cli/azure/containerapp) – complete list of parameters and examples for creating and managing container apps【344094499861713†L2928-L2938】.