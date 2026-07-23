# Key Vault module — parity with infrastructure/modules/keyvault.bicep.
# RBAC authorization, soft-delete 7d, purge protection ON.

variable "location" { type = string }
variable "resource_group_name" { type = string }
variable "name_prefix" { type = string }
variable "tags" { type = map(string) }
variable "tenant_id" { type = string }
variable "public_network_access" {
  type    = string
  default = "Enabled"
}

# kvName = take(replace('<prefix>kv<uniqueString>','-',''),24)
resource "random_string" "kv_suffix" {
  length  = 8
  special = false
  upper   = false
  numeric = true
}

locals {
  kv_name_raw = replace("${var.name_prefix}kv${random_string.kv_suffix.result}", "-", "")
  kv_name     = substr(local.kv_name_raw, 0, 24)
  public      = var.public_network_access == "Enabled"
}

resource "azurerm_key_vault" "this" {
  name                          = local.kv_name
  location                      = var.location
  resource_group_name           = var.resource_group_name
  tenant_id                     = var.tenant_id
  sku_name                      = "standard"
  tags                          = var.tags
  enable_rbac_authorization     = true # renamed to rbac_authorization_enabled in azurerm v5; kept for 4.x compatibility
  soft_delete_retention_days    = 7
  purge_protection_enabled      = true
  public_network_access_enabled = local.public

  network_acls {
    default_action = local.public ? "Allow" : "Deny"
    bypass         = "AzureServices"
  }
}

output "key_vault_id" { value = azurerm_key_vault.this.id }
output "key_vault_name" { value = azurerm_key_vault.this.name }
output "key_vault_uri" { value = azurerm_key_vault.this.vault_uri }
