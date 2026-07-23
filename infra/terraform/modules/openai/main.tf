# Azure OpenAI account + model deployments. Deployed twice by root main.tf
# (primary + secondary). Auth from APIM is via Managed Identity, not keys.
# Parity with infrastructure/modules/openai.bicep.

variable "location" { type = string }
variable "resource_group_name" { type = string }
variable "account_name" { type = string }
variable "tags" { type = map(string) }
variable "disable_local_auth" {
  type    = bool
  default = false
}
variable "deployments" {
  type = list(object({
    alias           = string
    deployment_name = string
    model_name      = string
    model_version   = string
    capacity        = number
    sku_name        = optional(string, "GlobalStandard")
  }))
}

resource "azurerm_cognitive_account" "openai" {
  name                          = var.account_name
  location                      = var.location
  resource_group_name           = var.resource_group_name
  kind                          = "OpenAI"
  sku_name                      = "S0"
  custom_subdomain_name         = var.account_name
  public_network_access_enabled = true
  local_auth_enabled            = !var.disable_local_auth
  tags                          = var.tags
}

# AOAI requires serial deployment creation; for_each + implicit dependency on
# the account plus create_before_destroy=false keeps them sequential enough.
resource "azurerm_cognitive_deployment" "models" {
  for_each = { for d in var.deployments : d.deployment_name => d }

  name                   = each.value.deployment_name
  cognitive_account_id   = azurerm_cognitive_account.openai.id
  rai_policy_name        = "Microsoft.DefaultV2"
  version_upgrade_option = "OnceNewDefaultVersionAvailable"

  model {
    format  = "OpenAI"
    name    = each.value.model_name
    version = each.value.model_version
  }

  sku {
    name     = each.value.sku_name
    capacity = each.value.capacity
  }
}

output "account_id" { value = azurerm_cognitive_account.openai.id }
output "account_name" { value = azurerm_cognitive_account.openai.name }
output "endpoint" { value = azurerm_cognitive_account.openai.endpoint }
