# =============================================================================
# Root outputs — mirror infrastructure/main.bicep. All use try(...) so they stay
# valid when a component is toggled off via its deploy_* boolean.
# =============================================================================

output "resource_group_name" {
  value = local.rg_name
}

output "apim_name" {
  value = try(module.apim[0].apim_name, null)
}

output "apim_gateway_url" {
  value = try(module.apim[0].apim_gateway_url, null)
}

output "apim_principal_id" {
  value = try(module.apim[0].apim_principal_id, null)
}

output "aoai_primary_endpoint" {
  value = try(module.openai_primary[0].endpoint, null)
}

output "aoai_secondary_endpoint" {
  value = try(module.openai_secondary[0].endpoint, null)
}

output "redis_host_name" {
  value = try(module.redis[0].redis_host_name, null)
}

output "redis_name" {
  value = try(module.redis[0].redis_name, null)
}

output "redis_database_name" {
  value = try(module.redis[0].redis_database_name, null)
}

output "redis_high_availability" {
  value = try(module.redis[0].redis_high_availability, null)
}

output "redis_redundancy_mode" {
  value = try(module.redis[0].redis_redundancy_mode, null)
}

output "redis_public_network_access" {
  value = try(module.redis[0].redis_public_network_access, null)
}

output "redis_private_endpoint_name" {
  value = try(module.redis_private_endpoint[0].private_endpoint_name, null)
}

output "vnet_name" {
  value = try(module.network[0].vnet_name, null)
}

output "key_vault_name" {
  value = try(module.keyvault[0].key_vault_name, null)
}

output "app_insights_connection_string" {
  value     = try(module.monitoring[0].app_insights_connection_string, null)
  sensitive = true
}

output "content_safety_endpoint" {
  value = local.content_safety_effective ? try(module.content_safety[0].endpoint, "") : ""
}

output "web_fqdn" {
  value = try(module.apps[0].web_fqdn, null)
}

output "foundry_primary_project_endpoint" {
  value = try(module.foundry_primary[0].project_endpoint, null)
}

output "foundry_secondary_project_endpoint" {
  value = try(module.foundry_secondary[0].project_endpoint, null)
}

# Foundry account/project/registry names — consumed by scripts/deploy-hosted-agent.sh
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

# ---- Shared MCP web-search --------------------------------------------------
output "enable_mcp_web_search" {
  value = var.enable_mcp_web_search
}

output "search_backend_url" {
  value = try(module.search_mcp[0].search_backend_url, null)
}

output "search_app_name" {
  value = try(module.search_mcp[0].search_app_name, null)
}
