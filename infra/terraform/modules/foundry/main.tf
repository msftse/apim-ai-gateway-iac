variable "location" { type = string }
variable "resource_group_name" { type = string }
variable "name_prefix" { type = string }
variable "tags" { type = map(string) }
variable "project_name" { type = string }
variable "site" { type = string }
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

resource "azurerm_cognitive_account" "foundry" {
  name                          = "${var.name_prefix}-foundry-${var.site}"
  location                      = var.location
  resource_group_name           = var.resource_group_name
  kind                          = "AIServices"
  sku_name                      = "S0"
  custom_subdomain_name         = lower("${var.name_prefix}-foundry-${var.site}")
  public_network_access_enabled = true
  # azurerm v4.81+ natively surfaces this (defaults false); set it here to match
  # the allowProjectManagement patch below, else azurerm forces a replacement.
  project_management_enabled = true
  identity { type = "SystemAssigned" }
  tags = var.tags
}

# azurerm does not surface `allowProjectManagement`, which is required before the
# account can host Foundry projects (parity with the Bicep path). Patch it on via
# azapi_update_resource so the child project below can be created.
resource "azapi_update_resource" "foundry_project_management" {
  type        = "Microsoft.CognitiveServices/accounts@2025-04-01-preview"
  resource_id = azurerm_cognitive_account.foundry.id
  body = {
    properties = {
      allowProjectManagement = true
    }
  }
}

resource "azapi_resource" "project" {
  type      = "Microsoft.CognitiveServices/accounts/projects@2025-04-01-preview"
  parent_id = azurerm_cognitive_account.foundry.id
  name      = "${var.project_name}-${var.site}"
  location  = var.location
  body = {
    identity = {
      type = "SystemAssigned"
    }
    properties = {}
  }
  response_export_values = ["identity.principalId"]
  depends_on             = [azapi_update_resource.foundry_project_management]
}

resource "azurerm_container_registry" "agent" {
  name                = replace(lower("${var.name_prefix}agentacr${var.site}"), "-", "")
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "Basic"
  admin_enabled       = false
  tags                = var.tags
}

resource "azurerm_role_assignment" "account_acr_pull" {
  scope                = azurerm_container_registry.agent.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_cognitive_account.foundry.identity[0].principal_id
}

resource "azurerm_role_assignment" "project_acr_pull" {
  scope                = azurerm_container_registry.agent.id
  role_definition_name = "AcrPull"
  principal_id         = azapi_resource.project.output.identity.principalId
}

resource "azapi_resource" "model" {
  for_each  = { for deployment in var.model_deployments : deployment.deployment_name => deployment }
  type      = "Microsoft.CognitiveServices/accounts/deployments@2025-10-01-preview"
  parent_id = azurerm_cognitive_account.foundry.id
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

output "foundry_account_name" { value = azurerm_cognitive_account.foundry.name }
output "project_endpoint" { value = "https://${azurerm_cognitive_account.foundry.custom_subdomain_name}.services.ai.azure.com/api/projects/${azapi_resource.project.name}" }
output "project_name" { value = azapi_resource.project.name }
output "registry_name" { value = azurerm_container_registry.agent.name }
output "registry_login_server" { value = azurerm_container_registry.agent.login_server }
output "account_id" { value = azurerm_cognitive_account.foundry.id }
output "project_id" { value = azapi_resource.project.id }
