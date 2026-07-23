# =============================================================================
# Shared MCP web-search backend — Terraform parity with
# infrastructure/modules/search-backend.bicep + role-search-keyvault.bicep.
#
# Deploys the web-search REST backend as a Container App with internal ingress,
# a system-assigned identity, and a Key Vault-referenced provider API key secret.
# Grants the app's identity Key Vault Secrets User so the secret reference
# resolves. The provider key VALUE is never in Terraform state as plaintext — it
# is a Key Vault secret referenced by URI.
#
# The APIM REST API + MCP server (type=mcp, api-version 2025-09-01-preview) are
# created post-deploy by scripts/configure-mcp-web-search.sh (shared by both the
# Bicep and Terraform paths), since APIM MCP resources have no azurerm support
# and are identical regardless of IaC tool.
# =============================================================================

variable "location" { type = string }
variable "resource_group_name" { type = string }
variable "name_prefix" { type = string }
variable "tags" { type = map(string) }
variable "container_app_environment_id" { type = string }
variable "app_insights_connection_string" {
  type      = string
  sensitive = true
}
variable "key_vault_id" { type = string }
variable "key_vault_uri" { type = string }
variable "api_key_secret_name" {
  type    = string
  default = "search-api-key"
}
variable "search_provider" {
  type    = string
  default = "tavily"
}
variable "search_api_endpoint" {
  type    = string
  default = "https://api.tavily.com/search"
}
variable "search_image" {
  type    = string
  default = "mcr.microsoft.com/k8se/quickstart:latest"
}

resource "azurerm_container_app" "search" {
  name                         = "${var.name_prefix}-search"
  resource_group_name          = var.resource_group_name
  container_app_environment_id = var.container_app_environment_id
  revision_mode                = "Single"
  tags                         = var.tags

  identity {
    type = "SystemAssigned"
  }

  # Provider API key resolved from Key Vault via the app managed identity. The
  # value is never written to state in clear text.
  secret {
    name                = "search-api-key"
    key_vault_secret_id = "${var.key_vault_uri}secrets/${var.api_key_secret_name}"
    identity            = "System"
  }

  ingress {
    external_enabled = false
    target_port      = 8082
    transport        = "auto"
    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  template {
    min_replicas = 1
    max_replicas = 3
    container {
      name   = "search"
      image  = var.search_image
      cpu    = 0.5
      memory = "1Gi"
      env {
        name  = "PORT"
        value = "8082"
      }
      env {
        name  = "SEARCH_PROVIDER"
        value = var.search_provider
      }
      env {
        name  = "SEARCH_API_ENDPOINT"
        value = var.search_api_endpoint
      }
      env {
        name  = "SEARCH_API_KEY_SECRET_NAME"
        value = var.api_key_secret_name
      }
      env {
        name        = "SEARCH_API_KEY"
        secret_name = "search-api-key"
      }
      env {
        name  = "APPLICATIONINSIGHTS_CONNECTION_STRING"
        value = var.app_insights_connection_string
      }
    }
  }
}

# Key Vault Secrets User for the search app identity.
resource "azurerm_role_assignment" "search_kv" {
  scope                = var.key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_container_app.search.identity[0].principal_id
}

output "search_app_name" { value = azurerm_container_app.search.name }
output "search_backend_url" { value = "https://${azurerm_container_app.search.ingress[0].fqdn}" }
output "search_app_principal_id" { value = azurerm_container_app.search.identity[0].principal_id }
