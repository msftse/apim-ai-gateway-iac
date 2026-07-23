# Reusable RBAC role assignment: APIM system-assigned identity -> a Cognitive
# Services / OpenAI account. Parity with infrastructure/modules/role-openai.bicep
# and role-content-safety.bicep (same shape, different built-in role id).
# Built-in role ids:
#   Cognitive Services OpenAI User: 5e0bd9bd-7b93-4f28-af87-19fc36ad61bd
#   Cognitive Services User:        a97b65f3-24c7-4388-baec-2e87135dc908

variable "principal_id" { type = string }
variable "scope_id" {
  description = "Resource ID of the target Cognitive Services / OpenAI account (the assignment scope)."
  type        = string
}
variable "role_definition_id" {
  description = "Built-in role definition GUID."
  type        = string
}

resource "azurerm_role_assignment" "this" {
  scope              = var.scope_id
  role_definition_id = "/providers/Microsoft.Authorization/roleDefinitions/${var.role_definition_id}"
  principal_id       = var.principal_id
  principal_type     = "ServicePrincipal"
}

output "role_assignment_id" { value = azurerm_role_assignment.this.id }
