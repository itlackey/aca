
  Recommended Changes (Todo List)

  High Priority - Alignment with Requirements

  - Rename example apps - Change APP1_NAME/APP2_NAME to web-hello/worker-service in .env.example
  and documentation
  - Create containerapp.yml templates - Add YAML config files for apps as specified in
  requirements (enables "update only when config changes")
  - Refactor deploy.sh - Change from hardcoded CLI to YAML-based az containerapp create --yaml
  approach
  - Add worker-service pattern - Include example with no ingress (background worker) to match
  requirements
  - Create azure-pipelines-image.yml - Template for app repos to build/push images to ACR
  - Create azure-pipelines-config.yml - Template for deploying when containerapp.yml changes
  - Secrets from Key Vault - Example showing Key Vault secret reference in containerapp.yml

  Medium Priority - Simplification

  - Split deploy.sh - Extract custom domain logic into separate configure-domains.sh script
  - Add defaults to .env.example - Make non-critical vars optional with sensible defaults (reduce
   required vars from ~25 to ~8)
  - Choose Azure DevOps as primary CI/CD - Document one as primary, move other to examples/ folder
  - Create deploy-app.sh generic script - Single script that deploys any app from its
  containerapp.yml

  Low Priority - Polish

  - Create app repo templates - Add templates/ folder with web-hello and worker-service scaffolds
  - Update RUNBOOK.md - Align steps with new YAML-based deployment
  - Add validation script - Script to verify containerapp.yml before deployment
  - Document app onboarding flow - Clear guide: create repo → copy template → configure → deploy
  - Parameter substitution in YAML - Support ${VAR} substitution in containerapp.yml
  - Health check endpoints - Add to example apps for production readiness

# Requirements

## Overview

This Azure Container Apps (ACA) based solution manages containerized applications for mostly intranet use with some public-facing sites. The platform serves low-traffic applications and is designed for production-grade deployments with robust onboarding capabilities.

## Infrastructure Requirements

### Core Azure Resources

- **Azure Container Apps Environment** - VNet-integrated environment for hosting containers
- **Virtual Network (VNet)** - with delegated subnets:
  - Infrastructure subnet for Container Apps environment
  - Private endpoint subnet for secure service access
- **Azure Container Registry (ACR)** - for storing and managing container images
- **Azure Key Vault** - for secure secret storage with RBAC enabled
- **Azure Storage Account** - for diagnostic logs with private endpoint access
- **Azure Monitor** - for monitoring and diagnostics
- **Private DNS Zone** - for private name resolution
- **Managed Identity** - for secure, passwordless access to ACR and Key Vault

### Repository Structure

- **Infrastructure repository** (`aca-platform-infra`) - separate repo for platform resources
- **Application repositories** - individual repos for each app (e.g., `web-hello`, `worker-service`)

## Deployment Requirements

### Infrastructure Deployment

- Bash scripts using Azure CLI for resource provisioning
- Support for both Azure DevOps and GitHub Actions pipelines
- Environment-specific configuration via `.env` files
- Idempotent operations for safe re-runs

### Application Deployment

- Containerized apps with `Dockerfile` and deployment scripts
- YAML configuration files (`containerapp.yml`) for ACA resource definitions
- Image build and push to ACR as primary deployment method
- Container app updates only when `containerapp.yml` changes
- Separate pipelines for:
  - Image builds (`azure-pipelines-image.yml`)
  - Configuration updates (`azure-pipelines-config.yml`)

### Security

- Private network access only where appropriate
- Managed identities for passwordless authentication
- Key Vault integration for secrets management
- RBAC permissions for least-privilege access

## Onboarding Requirements

### Documentation

- Production-ready, well-documented code and scripts
- Comprehensive README files in each repository
- Platform engineer runbook (`RUNBOOK.md`) integrating all components
- Clear examples suitable for new team member training

### Example Applications

- **web-hello** - Node.js web application with external ingress
- **worker-service** - Python background worker service
- Both apps deployable to personal/test resource groups for training

## CI/CD Requirements

### Pipeline Support

- Azure DevOps pipelines
- GitHub Actions workflows (alternative)
- Automated image builds on code changes
- Automated deployments on configuration changes
- Clear separation between infrastructure and application pipelines

## Operational Requirements

- Easy to understand and manage for platform engineers
- Robust error handling and validation
- Support for multiple environments (dev, test, prod)
- Clean resource isolation per environment or engineer
- No DNS forwarding needed