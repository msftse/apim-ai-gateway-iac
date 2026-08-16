# Foundry (AI Services) module — AVM-based.
#
# The Cognitive account and the agent Container Registry are provisioned with
# Azure Verified Modules. Two pieces have NO AVM coverage and remain azapi:
#   1. The Foundry *project* (Microsoft.CognitiveServices/accounts/projects) —
#      the AVM cognitive module only accepts project *names* via
#      `associated_projects` and does not surface the project's principalId,
#      which is required for the project's AcrPull role assignment below.
#   2. Provider-model deployments (Kimi/Llama/Claude) that need
#      `modelProviderData` — not expressible via the AVM `cognitive_deployments`
#      schema, so they stay on the deployments ARM API directly.

variable "location" { type = string }
variable "resource_group_name" { type = string }
variable "resource_group_id" { type = string }
variable "name_prefix" { type = string }
variable "tags" { type = map(string) }
variable "project_name" { type = string }
variable "site" { type = string }
# Optional suffix appended to the account name only (not the ACR / project).
# Used to sidestep a globally-reserved custom subdomain without forcing a
# replace of the other resources in this module.
variable "account_name_suffix" {
  type    = string
  default = ""
}
variable "model_deployments" {
  type = list(object({
    deployment_name = string
    model_name      = string
    model_version   = string
    model_format    = string
    sku_name        = string
    capacity        = number
    model_provider_data = optional(object({
      organization_name = string
      country_code      = string
      industry          = string
    }))
  }))
}

locals {
  account_name = "${var.name_prefix}-foundry-${var.site}${var.account_name_suffix}"
}

# ---- AI Services account (AVM) ----------------------------------------------
module "account" {
  source  = "Azure/avm-res-cognitiveservices-account/azurerm"
  version = "0.11.1"

  kind                          = "AIServices"
  name                          = local.account_name
  location                      = var.location
  parent_id                     = var.resource_group_id
  sku_name                      = "S0"
  custom_subdomain_name         = lower(local.account_name)
  public_network_access_enabled = true
  # Tenant enforces Entra-only auth (disableLocalAuth); listKeys is blocked.
  local_auth_enabled = false
  # Required before the account can host Foundry projects (parity with Bicep).
  allow_project_management = true
  tags                     = var.tags
  enable_telemetry         = false

  managed_identities = {
    system_assigned = true
  }
}

# ---- Foundry project (azapi — no AVM coverage) ------------------------------
resource "azapi_resource" "project" {
  type      = "Microsoft.CognitiveServices/accounts/projects@2025-04-01-preview"
  parent_id = module.account.resource_id
  name      = "${var.project_name}-${var.site}"
  location  = var.location
  body = {
    identity = {
      type = "SystemAssigned"
    }
    properties = {}
  }
  response_export_values = ["identity.principalId"]
}

# ---- Agent Container Registry (AVM) -----------------------------------------
module "registry" {
  source  = "Azure/avm-res-containerregistry-registry/azurerm"
  version = "0.8.0"

  name                    = replace(lower("${var.name_prefix}agentacr${var.site}"), "-", "")
  location                = var.location
  resource_group_name     = var.resource_group_name
  sku                     = "Basic"
  admin_enabled           = false
  zone_redundancy_enabled = false # required: zone redundancy needs Premium SKU
  tags                    = var.tags
  enable_telemetry        = false

  # AcrPull for both the account MI and the project MI, via the AVM
  # role_assignments interface (replaces the standalone role-assignment module).
  role_assignments = {
    account_acr_pull = {
      role_definition_id_or_name = "AcrPull"
      principal_id               = module.account.system_assigned_mi_principal_id
      principal_type             = "ServicePrincipal"
    }
    project_acr_pull = {
      role_definition_id_or_name = "AcrPull"
      principal_id               = azapi_resource.project.output.identity.principalId
      principal_type             = "ServicePrincipal"
    }
  }
}

# ---- Model deployments (azapi — needs modelProviderData) --------------------
resource "azapi_resource" "model" {
  for_each  = { for deployment in var.model_deployments : deployment.deployment_name => deployment }
  type      = "Microsoft.CognitiveServices/accounts/deployments@2025-10-01-preview"
  parent_id = module.account.resource_id
  name      = each.value.deployment_name
  body = {
    sku = {
      name     = each.value.sku_name
      capacity = each.value.capacity
    }
    properties = jsondecode(each.value.model_provider_data == null ? jsonencode({
      model = {
        format  = each.value.model_format
        name    = each.value.model_name
        version = each.value.model_version
      }
      versionUpgradeOption = "OnceNewDefaultVersionAvailable"
      raiPolicyName        = "Microsoft.DefaultV2"
      }) : jsonencode({
      model = {
        format  = each.value.model_format
        name    = each.value.model_name
        version = each.value.model_version
      }
      modelProviderData = {
        organizationName = each.value.model_provider_data.organization_name
        countryCode      = each.value.model_provider_data.country_code
        industry         = each.value.model_provider_data.industry
      }
      versionUpgradeOption = "OnceNewDefaultVersionAvailable"
      raiPolicyName        = "Microsoft.DefaultV2"
    }))
  }
  schema_validation_enabled = false
}

output "foundry_account_name" { value = module.account.name }
output "project_endpoint" { value = "https://${lower(local.account_name)}.services.ai.azure.com/api/projects/${azapi_resource.project.name}" }
output "project_name" { value = azapi_resource.project.name }
output "registry_name" { value = module.registry.name }
output "registry_login_server" { value = module.registry.login_server }
output "account_id" { value = module.account.resource_id }
output "project_id" { value = azapi_resource.project.id }
