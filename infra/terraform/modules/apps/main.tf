# Container Apps environment + web app shell. Images are pushed
# later by scripts/apps-deploy.sh. Parity with infrastructure/modules/apps.bicep.

variable "location" { type = string }
variable "resource_group_name" { type = string }
variable "name_prefix" { type = string }
variable "tags" { type = map(string) }
variable "log_analytics_workspace_id" { type = string }
variable "web_image" {
  type    = string
  default = "mcr.microsoft.com/k8se/quickstart:latest"
}
variable "app_insights_connection_string" {
  type      = string
  sensitive = true
}
variable "apim_gateway_url" { type = string }

resource "azurerm_container_app_environment" "this" {
  name                       = "${var.name_prefix}-cae"
  location                   = var.location
  resource_group_name        = var.resource_group_name
  log_analytics_workspace_id = var.log_analytics_workspace_id
  tags                       = var.tags
}

resource "azurerm_container_app" "web" {
  name                         = "${var.name_prefix}-web"
  resource_group_name          = var.resource_group_name
  container_app_environment_id = azurerm_container_app_environment.this.id
  revision_mode                = "Single"
  tags                         = var.tags

  identity {
    type = "SystemAssigned"
  }

  ingress {
    external_enabled = true
    target_port      = 3000
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
      name   = "web"
      image  = var.web_image
      cpu    = 0.5
      memory = "1Gi"
      env {
        name  = "NEXT_PUBLIC_APIM_GATEWAY_URL"
        value = var.apim_gateway_url
      }
      env {
        name  = "APPLICATIONINSIGHTS_CONNECTION_STRING"
        value = var.app_insights_connection_string
      }
    }
  }
}

output "environment_id" { value = azurerm_container_app_environment.this.id }
output "web_fqdn" { value = azurerm_container_app.web.ingress[0].fqdn }
