# =============================================================================
# Root outputs — mirror infrastructure/main.bicep. All use try(...) so they stay
# valid when a component is toggled off via its deploy_* boolean.
# =============================================================================

output "resource_group_name" {
  value = local.rg_name
}

output "apim_name" {
  value = try(module.apim[0].name, null)
}

output "apim_gateway_url" {
  value = try(module.apim[0].apim_gateway_url, null)
}

output "apim_principal_id" {
  # Derived from the AVM module's `resource` output, which is marked sensitive
  # in its entirety; Terraform requires the propagation be acknowledged.
  sensitive = true
  value     = try(module.apim[0].resource.identity[0].principal_id, null)
}

output "aoai_primary_endpoint" {
  value = try(module.openai_primary[0].endpoint, null)
}

output "aoai_secondary_endpoint" {
  value = try(module.openai_secondary[0].endpoint, null)
}

output "redis_host_name" {
  value = try(module.redis[0].hostname, null)
}

output "redis_name" {
  value = try(module.redis[0].name, null)
}

output "redis_database_name" {
  value = try(module.redis[0].database.name, "default")
}

output "redis_high_availability" {
  value = try(module.redis[0].resource.high_availability, var.redis_high_availability)
}

output "redis_redundancy_mode" {
  value = try(module.redis[0].resource.redundancy_mode, "Unknown")
}

output "redis_public_network_access" {
  value = try(module.redis[0].resource.public_network_access, "Disabled")
}

output "redis_private_endpoint_name" {
  value = try(values(module.redis[0].private_endpoints)[0].name, null)
}

output "vnet_name" {
  value = try(module.network[0].name, null)
}

output "key_vault_name" {
  value = try(module.keyvault[0].name, null)
}

output "app_insights_connection_string" {
  value     = try(module.app_insights[0].connection_string, null)
  sensitive = true
}

output "content_safety_endpoint" {
  value = local.content_safety_effective ? try(module.content_safety[0].endpoint, "") : ""
}

output "foundry_primary_project_endpoint" {
  value = try(module.foundry_primary[0].project_endpoint, null)
}

output "foundry_secondary_project_endpoint" {
  value = try(module.foundry_secondary[0].project_endpoint, null)
}

# Foundry account/project/registry names.
output "foundry_primary_account_name" {
  value = try(module.foundry_primary[0].foundry_account_name, null)
}
output "foundry_primary_project_name" {
  value = try(module.foundry_primary[0].project_name, null)
}
output "foundry_primary_registry_name" {
  value = try(module.foundry_primary[0].registry_name, null)
}
output "foundry_secondary_account_name" {
  value = try(module.foundry_secondary[0].foundry_account_name, null)
}
output "foundry_secondary_project_name" {
  value = try(module.foundry_secondary[0].project_name, null)
}
output "foundry_secondary_registry_name" {
  value = try(module.foundry_secondary[0].registry_name, null)
}
