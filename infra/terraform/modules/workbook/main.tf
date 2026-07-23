# Azure Monitor workbook for the AI Gateway. The Bicep path deploys this via
# scripts/deploy-workbook.sh using monitoring/workbook-ai-gateway.json; Terraform
# deploys the same JSON declaratively for parity.

variable "location" { type = string }
variable "resource_group_name" { type = string }
variable "name_prefix" { type = string }
variable "tags" { type = map(string) }
variable "log_analytics_id" { type = string }
variable "workbook_json_path" {
  description = "Path to the workbook definition JSON (monitoring/workbook-ai-gateway.json)."
  type        = string
}

resource "random_uuid" "workbook" {}

resource "azurerm_application_insights_workbook" "this" {
  name                = random_uuid.workbook.result
  location            = var.location
  resource_group_name = var.resource_group_name
  display_name        = "${var.name_prefix} — Enterprise AI Gateway"
  source_id           = lower(var.log_analytics_id)
  data_json           = file(var.workbook_json_path)
  tags                = var.tags
}

output "workbook_id" { value = azurerm_application_insights_workbook.this.id }
