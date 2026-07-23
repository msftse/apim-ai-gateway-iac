# =============================================================================
# Root composition — creates the resource group and orchestrates all modules,
# mirroring infrastructure/main.bicep. Every independently-created component is
# gated by a deploy_* boolean (Part 3) using module count, and downstream
# references use try(...) so a skipped component never breaks the graph.
# =============================================================================

# ---- Resource group (create or reuse existing) ------------------------------
resource "azurerm_resource_group" "this" {
  count    = var.deploy_resource_group ? 1 : 0
  name     = "${local.name_prefix}-rg"
  location = var.location
  tags     = local.tags
}

data "azurerm_resource_group" "existing" {
  count = var.deploy_resource_group ? 0 : 1
  name  = var.existing_resource_group_name
}

locals {
  rg_name = var.deploy_resource_group ? azurerm_resource_group.this[0].name : data.azurerm_resource_group.existing[0].name
  rg_id   = var.deploy_resource_group ? azurerm_resource_group.this[0].id : data.azurerm_resource_group.existing[0].id

  # Built-in role definition GUIDs.
  role_openai_user             = "5e0bd9bd-7b93-4f28-af87-19fc36ad61bd"
  role_cognitive_services_user = "a97b65f3-24c7-4388-baec-2e87135dc908"
  role_foundry_account_owner   = "e47c6f54-e4a2-4754-9501-8e0985b135e1"
  role_foundry_agent_consumer  = "eed3b665-ab3a-47b6-8f48-c9382fb1dad6"

  workbook_json_path = "${path.module}/../../monitoring/workbook-ai-gateway.json"

  foundry_optional_model_deployments = concat(
    var.enable_foundry_kimi ? [{
      deployment_name = "kimi-k2-5"
      model_name      = "Kimi-K2.5"
      model_version   = "1"
      model_format    = "MoonshotAI"
      sku_name        = "GlobalStandard"
      capacity        = 10
    }] : [],
    var.enable_foundry_llama ? [{
      deployment_name = "llama-3-3-70b-instruct"
      model_name      = "Llama-3.3-70B-Instruct"
      model_version   = "1"
      model_format    = "Meta"
      sku_name        = "GlobalStandard"
      capacity        = 10
    }] : [],
    var.enable_foundry_claude ? [{
      deployment_name = "claude-sonnet-4-6"
      model_name      = "claude-sonnet-4-6"
      model_version   = "1"
      model_format    = "Anthropic"
      sku_name        = "GlobalStandard"
      capacity        = 25
      model_provider_data = {
        organization_name = var.foundry_claude_organization_name
        country_code      = var.foundry_claude_country_code
        industry          = var.foundry_claude_industry
      }
    }] : []
  )
}

# ---- Monitoring -------------------------------------------------------------
module "monitoring" {
  count  = var.deploy_log_analytics || var.deploy_application_insights ? 1 : 0
  source = "./modules/monitoring"

  location                            = var.location
  resource_group_name                 = local.rg_name
  name_prefix                         = local.name_prefix
  tags                                = local.tags
  retention_in_days                   = var.log_retention_in_days
  deploy_log_analytics                = var.deploy_log_analytics
  deploy_application_insights         = var.deploy_application_insights
  existing_log_analytics_workspace_id = var.existing_log_analytics_workspace_id
}

# ---- Key Vault --------------------------------------------------------------
module "keyvault" {
  count  = var.deploy_key_vault ? 1 : 0
  source = "./modules/keyvault"

  location              = var.location
  resource_group_name   = local.rg_name
  name_prefix           = local.name_prefix
  tags                  = local.tags
  tenant_id             = data.azurerm_client_config.current.tenant_id
  public_network_access = var.networking_mode == "public" ? "Enabled" : "Disabled"
}

# ---- Networking -------------------------------------------------------------
module "network" {
  count  = var.deploy_virtual_network ? 1 : 0
  source = "./modules/network"

  location            = var.location
  resource_group_name = local.rg_name
  name_prefix         = local.name_prefix
  tags                = local.tags
  deploy_private_dns  = var.deploy_private_dns
}

# ---- Redis ------------------------------------------------------------------
module "redis" {
  count  = var.deploy_redis ? 1 : 0
  source = "./modules/redis"

  location              = var.redis_location
  resource_group_id     = local.rg_id
  name_prefix           = local.name_prefix
  tags                  = local.tags
  sku_name              = var.redis_sku
  high_availability     = var.redis_high_availability
  public_network_access = "Disabled"
}

module "redis_private_endpoint" {
  count  = var.deploy_redis && var.deploy_private_endpoints ? 1 : 0
  source = "./modules/redis-private-endpoint"

  location               = var.redis_location
  resource_group_name    = local.rg_name
  name_prefix            = local.name_prefix
  tags                   = local.tags
  redis_id               = module.redis[0].redis_id
  private_link_subnet_id = local.private_link_subnet_id
  redis_dns_zone_id      = local.redis_dns_zone_id
}

# ---- Content Safety (optional) ----------------------------------------------
module "content_safety" {
  count  = local.content_safety_effective ? 1 : 0
  source = "./modules/content-safety"

  location            = var.location
  resource_group_name = local.rg_name
  name_prefix         = local.name_prefix
  tags                = local.tags
}

# ---- Azure OpenAI: primary + secondary --------------------------------------
module "openai_primary" {
  count  = var.deploy_primary_azure_openai ? 1 : 0
  source = "./modules/openai"

  location            = var.location
  resource_group_name = local.rg_name
  account_name        = "${local.name_prefix}-aoai-primary"
  tags                = local.tags
  deployments         = var.primary_deployments
}

module "openai_secondary" {
  count  = var.deploy_secondary_azure_openai ? 1 : 0
  source = "./modules/openai"

  location            = var.secondary_location
  resource_group_name = local.rg_name
  account_name        = "${local.name_prefix}-aoai-secondary"
  tags                = local.tags
  deployments         = var.secondary_deployments
}

module "foundry_primary" {
  count  = var.deploy_foundry ? 1 : 0
  source = "./modules/foundry"

  location            = var.location
  resource_group_name = local.rg_name
  name_prefix         = local.name_prefix
  tags                = local.tags
  project_name        = var.foundry_project_name
  site                = "primary"
  model_deployments   = concat(var.foundry_model_deployments, local.foundry_optional_model_deployments)
}

module "foundry_secondary" {
  count  = var.deploy_foundry ? 1 : 0
  source = "./modules/foundry"

  location            = var.foundry_secondary_location
  resource_group_name = local.rg_name
  name_prefix         = local.name_prefix
  tags                = local.tags
  project_name        = var.foundry_project_name
  site                = "secondary"
  model_deployments   = concat(var.foundry_model_deployments, local.foundry_optional_model_deployments)
}

# ---- APIM -------------------------------------------------------------------
module "apim" {
  count  = var.deploy_apim ? 1 : 0
  source = "./modules/apim"

  location                         = var.location
  resource_group_name              = local.rg_name
  name_prefix                      = local.name_prefix
  tags                             = local.tags
  sku_name                         = var.apim_sku
  sku_capacity                     = var.apim_sku_capacity
  publisher_email                  = var.publisher_email
  publisher_name                   = var.publisher_name
  app_insights_id                  = try(module.monitoring[0].app_insights_id, null)
  app_insights_instrumentation_key = try(module.monitoring[0].app_insights_instrumentation_key, null)
  log_analytics_id                 = local.log_analytics_id
  named_values                     = {} # named values now owned by module.apim_config
  subnet_id                        = local.apim_subnet_id
  virtual_network_type             = local.apim_virtual_network_type
  deploy_diagnostic_settings       = var.deploy_diagnostic_settings
}

# ---- APIM control plane (APIs, backends, pool, policies, products, cache) ----
module "apim_config" {
  count  = var.deploy_apim ? 1 : 0
  source = "./modules/apim-config"

  apim_id            = module.apim[0].apim_id
  policy_dir         = "${path.module}/../../apim/policies"
  products_json_path = "${path.module}/../../apim/products/products.json"
  named_values       = local.apim_named_values

  enable_gateway_api            = var.enable_gateway_api
  enable_load_balancing         = var.enable_load_balancing
  enable_semantic_cache         = var.enable_semantic_cache
  enable_content_safety         = local.content_safety_effective
  enable_products               = var.enable_products
  enable_hosted_agent           = var.enable_hosted_agent && var.deploy_foundry
  enable_mcp_web_search         = var.enable_mcp_governance && var.enable_mcp_web_search && var.deploy_apps && var.deploy_key_vault
  enable_model_alias_management = var.enable_model_alias_management
  enable_advanced_observability = var.enable_advanced_observability
  deploy_secondary_azure_openai = var.deploy_secondary_azure_openai

  aoai_primary_endpoint      = try(module.openai_primary[0].endpoint, "")
  aoai_secondary_endpoint    = try(module.openai_secondary[0].endpoint, "")
  embeddings_url             = var.enable_semantic_cache ? "${trimsuffix(try(module.openai_primary[0].endpoint, ""), "/")}/openai/deployments/text-embedding-3-small/embeddings" : ""
  content_safety_endpoint    = local.content_safety_effective ? try(module.content_safety[0].endpoint, "") : ""
  foundry_primary_endpoint   = var.deploy_foundry ? try(module.foundry_primary[0].project_endpoint, "") : ""
  foundry_secondary_endpoint = var.deploy_foundry ? try(module.foundry_secondary[0].project_endpoint, "") : ""
  web_search_backend_url     = try(module.search_mcp[0].search_backend_url, "")

  redis_database_id = var.enable_semantic_cache ? try(module.redis[0].redis_database_id, "") : ""
  redis_host_name   = var.enable_semantic_cache ? try(module.redis[0].redis_host_name, "") : ""
}

# ---- Role assignments: APIM identity -> backends ----------------------------
module "role_primary" {
  count  = var.deploy_role_assignments && var.deploy_apim && var.deploy_primary_azure_openai ? 1 : 0
  source = "./modules/role-assignment"

  principal_id       = module.apim[0].apim_principal_id
  scope_id           = module.openai_primary[0].account_id
  role_definition_id = local.role_openai_user
}

module "role_secondary" {
  count  = var.deploy_role_assignments && var.deploy_apim && var.deploy_secondary_azure_openai ? 1 : 0
  source = "./modules/role-assignment"

  principal_id       = module.apim[0].apim_principal_id
  scope_id           = module.openai_secondary[0].account_id
  role_definition_id = local.role_openai_user
}

module "role_content_safety" {
  count  = var.deploy_role_assignments && var.deploy_apim && local.content_safety_effective ? 1 : 0
  source = "./modules/role-assignment"

  principal_id       = module.apim[0].apim_principal_id
  scope_id           = module.content_safety[0].account_id
  role_definition_id = local.role_cognitive_services_user
}

module "role_foundry_primary_account" {
  count              = var.deploy_role_assignments && var.deploy_apim && var.deploy_foundry ? 1 : 0
  source             = "./modules/role-assignment"
  principal_id       = module.apim[0].apim_principal_id
  scope_id           = module.foundry_primary[0].account_id
  role_definition_id = local.role_foundry_account_owner
}

module "role_foundry_primary_project_owner" {
  count              = var.deploy_role_assignments && var.deploy_apim && var.deploy_foundry ? 1 : 0
  source             = "./modules/role-assignment"
  principal_id       = module.apim[0].apim_principal_id
  scope_id           = module.foundry_primary[0].project_id
  role_definition_id = local.role_foundry_account_owner
}

module "role_foundry_primary_agent_consumer" {
  count              = var.deploy_role_assignments && var.deploy_apim && var.deploy_foundry ? 1 : 0
  source             = "./modules/role-assignment"
  principal_id       = module.apim[0].apim_principal_id
  scope_id           = module.foundry_primary[0].project_id
  role_definition_id = local.role_foundry_agent_consumer
}

module "role_foundry_secondary_account" {
  count              = var.deploy_role_assignments && var.deploy_apim && var.deploy_foundry ? 1 : 0
  source             = "./modules/role-assignment"
  principal_id       = module.apim[0].apim_principal_id
  scope_id           = module.foundry_secondary[0].account_id
  role_definition_id = local.role_foundry_account_owner
}

module "role_foundry_secondary_project_owner" {
  count              = var.deploy_role_assignments && var.deploy_apim && var.deploy_foundry ? 1 : 0
  source             = "./modules/role-assignment"
  principal_id       = module.apim[0].apim_principal_id
  scope_id           = module.foundry_secondary[0].project_id
  role_definition_id = local.role_foundry_account_owner
}

module "role_foundry_secondary_agent_consumer" {
  count              = var.deploy_role_assignments && var.deploy_apim && var.deploy_foundry ? 1 : 0
  source             = "./modules/role-assignment"
  principal_id       = module.apim[0].apim_principal_id
  scope_id           = module.foundry_secondary[0].project_id
  role_definition_id = local.role_foundry_agent_consumer
}

# ---- Application hosting -----------------------------------------------------
module "apps" {
  count  = var.deploy_apps ? 1 : 0
  source = "./modules/apps"

  location                       = var.location
  resource_group_name            = local.rg_name
  name_prefix                    = local.name_prefix
  tags                           = local.tags
  log_analytics_workspace_id     = local.log_analytics_id
  web_image                      = var.container_web_image
  app_insights_connection_string = try(module.monitoring[0].app_insights_connection_string, "")
  apim_gateway_url               = try(module.apim[0].apim_gateway_url, "")
}

# ---- Shared MCP web-search backend (gated) ----------------------------------
module "search_mcp" {
  count  = var.enable_mcp_governance && var.enable_mcp_web_search && var.deploy_apps && var.deploy_key_vault ? 1 : 0
  source = "./modules/search-mcp"

  location                       = var.location
  resource_group_name            = local.rg_name
  name_prefix                    = local.name_prefix
  tags                           = local.tags
  container_app_environment_id   = module.apps[0].environment_id
  app_insights_connection_string = try(module.monitoring[0].app_insights_connection_string, "")
  key_vault_id                   = module.keyvault[0].key_vault_id
  key_vault_uri                  = module.keyvault[0].key_vault_uri
  api_key_secret_name            = var.search_api_key_secret_name
  search_provider                = var.search_provider
  search_api_endpoint            = var.search_api_endpoint
}

# ---- Workbook ---------------------------------------------------------------
module "workbook" {
  count  = var.deploy_workbook ? 1 : 0
  source = "./modules/workbook"

  location            = var.location
  resource_group_name = local.rg_name
  name_prefix         = local.name_prefix
  tags                = local.tags
  log_analytics_id    = local.log_analytics_id
  workbook_json_path  = local.workbook_json_path
}
