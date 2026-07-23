# Azure AI Content Safety account. Parity with
# infrastructure/modules/content-safety.bicep.

variable "location" { type = string }
variable "resource_group_name" { type = string }
variable "name_prefix" { type = string }
variable "tags" { type = map(string) }

locals {
  account_name = "${var.name_prefix}-safety"
}

resource "azurerm_cognitive_account" "content_safety" {
  name                          = local.account_name
  location                      = var.location
  resource_group_name           = var.resource_group_name
  kind                          = "ContentSafety"
  sku_name                      = "S0"
  custom_subdomain_name         = local.account_name
  public_network_access_enabled = true
  local_auth_enabled            = true
  tags                          = var.tags
}

output "account_id" { value = azurerm_cognitive_account.content_safety.id }
output "account_name" { value = azurerm_cognitive_account.content_safety.name }
output "endpoint" { value = azurerm_cognitive_account.content_safety.endpoint }
