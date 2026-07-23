# Azure API Management — the AI Gateway control plane. System-assigned identity,
# App Insights logger + diagnostic, named values, and diagnostic settings to Log
# Analytics. Policies/APIs are applied post-deploy by scripts/configure-apim.sh.
# Parity with infrastructure/modules/apim.bicep.

variable "location" { type = string }
variable "resource_group_name" { type = string }
variable "name_prefix" { type = string }
variable "tags" { type = map(string) }
variable "sku_name" {
  type    = string
  default = "Developer"
}
variable "sku_capacity" {
  type    = number
  default = 1
}
variable "publisher_email" { type = string }
variable "publisher_name" { type = string }
variable "app_insights_id" { type = string }
variable "app_insights_instrumentation_key" {
  type      = string
  sensitive = true
}
variable "log_analytics_id" {
  type    = string
  default = null
}
variable "named_values" {
  type    = map(string)
  default = {}
}
variable "subnet_id" {
  type    = string
  default = null
}
variable "virtual_network_type" {
  type    = string
  default = "None"
}
variable "deploy_diagnostic_settings" {
  type    = bool
  default = true
}

locals {
  # Developer SKU is forced to capacity 1 (parity with Bicep).
  effective_capacity = var.sku_name == "Developer" ? 1 : var.sku_capacity
  sku                = "${var.sku_name}_${local.effective_capacity}"
}

resource "azurerm_api_management" "this" {
  name                 = "${var.name_prefix}-apim"
  location             = var.location
  resource_group_name  = var.resource_group_name
  publisher_email      = var.publisher_email
  publisher_name       = var.publisher_name
  sku_name             = local.sku
  virtual_network_type = var.virtual_network_type
  tags                 = var.tags

  identity {
    type = "SystemAssigned"
  }

  dynamic "virtual_network_configuration" {
    for_each = var.virtual_network_type == "None" ? [] : [1]
    content {
      subnet_id = var.subnet_id
    }
  }
}

resource "azurerm_api_management_logger" "appinsights" {
  name                = "appinsights-logger"
  api_management_name = azurerm_api_management.this.name
  resource_group_name = var.resource_group_name
  resource_id         = var.app_insights_id

  application_insights {
    instrumentation_key = var.app_insights_instrumentation_key
  }
}

resource "azurerm_api_management_diagnostic" "appinsights" {
  identifier               = "applicationinsights"
  api_management_name      = azurerm_api_management.this.name
  resource_group_name      = var.resource_group_name
  api_management_logger_id = azurerm_api_management_logger.appinsights.id

  always_log_errors         = true
  verbosity                 = "verbose"
  http_correlation_protocol = "W3C"
  log_client_ip             = true
  sampling_percentage       = 100
}

resource "azurerm_api_management_named_value" "this" {
  # Named values are now owned by the apim-config module (single source of
  # truth). Kept empty here for back-compat; pass named_values = {} from root.
  for_each            = var.named_values
  name                = each.key
  display_name        = each.key
  api_management_name = azurerm_api_management.this.name
  resource_group_name = var.resource_group_name
  value               = each.value
  secret              = false
}

resource "azurerm_monitor_diagnostic_setting" "apim" {
  count                      = var.deploy_diagnostic_settings && var.log_analytics_id != null ? 1 : 0
  name                       = "apim-diagnostics"
  target_resource_id         = azurerm_api_management.this.id
  log_analytics_workspace_id = var.log_analytics_id

  enabled_log {
    category_group = "allLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

output "apim_id" { value = azurerm_api_management.this.id }
output "apim_name" { value = azurerm_api_management.this.name }
output "apim_gateway_url" { value = azurerm_api_management.this.gateway_url }
output "apim_principal_id" { value = azurerm_api_management.this.identity[0].principal_id }
output "apim_logger_id" { value = azurerm_api_management_logger.appinsights.id }
