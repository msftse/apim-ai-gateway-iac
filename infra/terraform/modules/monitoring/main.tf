# Monitoring module — Log Analytics workspace + workspace-based Application
# Insights. Parity with infrastructure/modules/monitoring.bicep.

variable "location" { type = string }
variable "resource_group_name" { type = string }
variable "name_prefix" { type = string }
variable "tags" { type = map(string) }
variable "retention_in_days" {
  type    = number
  default = 30
}
variable "deploy_log_analytics" {
  type    = bool
  default = true
}
variable "deploy_application_insights" {
  type    = bool
  default = true
}
# Used when deploy_log_analytics = false so App Insights can bind to an existing workspace.
variable "existing_log_analytics_workspace_id" {
  type    = string
  default = ""
}

resource "azurerm_log_analytics_workspace" "this" {
  count               = var.deploy_log_analytics ? 1 : 0
  name                = "${var.name_prefix}-law"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = var.retention_in_days
  tags                = var.tags
  # Parity with enableLogAccessUsingOnlyResourcePermissions: true
  local_authentication_disabled = false
}

locals {
  workspace_id = var.deploy_log_analytics ? azurerm_log_analytics_workspace.this[0].id : var.existing_log_analytics_workspace_id
}

resource "azurerm_application_insights" "this" {
  count               = var.deploy_application_insights ? 1 : 0
  name                = "${var.name_prefix}-appi"
  location            = var.location
  resource_group_name = var.resource_group_name
  application_type    = "web"
  workspace_id        = local.workspace_id
  tags                = var.tags
}

output "log_analytics_id" {
  value = try(azurerm_log_analytics_workspace.this[0].id, var.existing_log_analytics_workspace_id)
}
output "log_analytics_name" {
  value = try(azurerm_log_analytics_workspace.this[0].name, null)
}
output "log_analytics_customer_id" {
  value = try(azurerm_log_analytics_workspace.this[0].workspace_id, null)
}
output "app_insights_id" {
  value = try(azurerm_application_insights.this[0].id, null)
}
output "app_insights_name" {
  value = try(azurerm_application_insights.this[0].name, null)
}
output "app_insights_connection_string" {
  value     = try(azurerm_application_insights.this[0].connection_string, null)
  sensitive = true
}
output "app_insights_instrumentation_key" {
  value     = try(azurerm_application_insights.this[0].instrumentation_key, null)
  sensitive = true
}
