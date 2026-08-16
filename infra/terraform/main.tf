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

# ---- Monitoring: Log Analytics workspace (AVM) ------------------------------
module "log_analytics" {
  count   = var.deploy_log_analytics ? 1 : 0
  source  = "Azure/avm-res-operationalinsights-workspace/azurerm"
  version = "0.5.1"

  name                = "${local.name_prefix}-law"
  location            = var.location
  resource_group_name = local.rg_name
  tags                = local.tags

  log_analytics_workspace_sku               = "PerGB2018"
  log_analytics_workspace_retention_in_days = var.log_retention_in_days
  # Parity with enableLogAccessUsingOnlyResourcePermissions: true
  log_analytics_workspace_allow_resource_only_permissions = true

  enable_telemetry = false
}

# ---- Monitoring: workspace-based Application Insights (AVM) ------------------
module "app_insights" {
  count   = var.deploy_application_insights ? 1 : 0
  source  = "Azure/avm-res-insights-component/azurerm"
  version = "0.4.0"

  name                = "${local.name_prefix}-appi"
  location            = var.location
  resource_group_name = local.rg_name
  tags                = local.tags
  application_type    = "web"
  workspace_id        = local.log_analytics_id

  enable_telemetry = false
}

# ---- Key Vault (AVM) --------------------------------------------------------
# kvName = take(replace('<prefix>kv<uniqueString>','-',''),24)
resource "random_string" "kv_suffix" {
  count   = var.deploy_key_vault ? 1 : 0
  length  = 8
  special = false
  upper   = false
  numeric = true
}

module "keyvault" {
  count   = var.deploy_key_vault ? 1 : 0
  source  = "Azure/avm-res-keyvault-vault/azurerm"
  version = "0.11.0"

  name                = substr(replace("${local.name_prefix}kv${random_string.kv_suffix[0].result}", "-", ""), 0, 24)
  location            = var.location
  resource_group_name = local.rg_name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  tags                = local.tags

  sku_name                      = "standard"
  soft_delete_retention_days    = 7
  purge_protection_enabled      = true
  public_network_access_enabled = var.networking_mode == "public"

  network_acls = {
    bypass         = "AzureServices"
    default_action = var.networking_mode == "public" ? "Allow" : "Deny"
  }

  # RBAC authorization is the AVM default; no legacy access policies.
  legacy_access_policies_enabled = false
  enable_telemetry               = false
}

# ---- Networking: NSG (AVM) --------------------------------------------------
# Minimum rules for classic External-mode APIM injection.
module "apim_nsg" {
  count   = var.deploy_virtual_network ? 1 : 0
  source  = "Azure/avm-res-network-networksecuritygroup/azurerm"
  version = "0.5.1"

  name                = "${local.name_prefix}-apim-nsg"
  location            = var.location
  resource_group_name = local.rg_name
  tags                = local.tags

  security_rules = {
    In-Client-443 = {
      name                       = "In-Client-443"
      direction                  = "Inbound"
      access                     = "Allow"
      priority                   = 100
      protocol                   = "Tcp"
      source_address_prefix      = "Internet"
      source_port_range          = "*"
      destination_address_prefix = "VirtualNetwork"
      destination_port_ranges    = ["80", "443"]
    }
    In-Management-3443 = {
      name                       = "In-Management-3443"
      direction                  = "Inbound"
      access                     = "Allow"
      priority                   = 110
      protocol                   = "Tcp"
      source_address_prefix      = "ApiManagement"
      source_port_range          = "*"
      destination_address_prefix = "VirtualNetwork"
      destination_port_range     = "3443"
    }
    In-LoadBalancer-6390 = {
      name                       = "In-LoadBalancer-6390"
      direction                  = "Inbound"
      access                     = "Allow"
      priority                   = 120
      protocol                   = "Tcp"
      source_address_prefix      = "AzureLoadBalancer"
      source_port_range          = "*"
      destination_address_prefix = "VirtualNetwork"
      destination_port_range     = "6390"
    }
    In-TrafficManager-443 = {
      name                       = "In-TrafficManager-443"
      direction                  = "Inbound"
      access                     = "Allow"
      priority                   = 130
      protocol                   = "Tcp"
      source_address_prefix      = "AzureTrafficManager"
      source_port_range          = "*"
      destination_address_prefix = "VirtualNetwork"
      destination_port_range     = "443"
    }
    Out-Storage-443 = {
      name                       = "Out-Storage-443"
      direction                  = "Outbound"
      access                     = "Allow"
      priority                   = 100
      protocol                   = "Tcp"
      source_address_prefix      = "VirtualNetwork"
      source_port_range          = "*"
      destination_address_prefix = "Storage"
      destination_port_range     = "443"
    }
    Out-SQL-1433 = {
      name                       = "Out-SQL-1433"
      direction                  = "Outbound"
      access                     = "Allow"
      priority                   = 110
      protocol                   = "Tcp"
      source_address_prefix      = "VirtualNetwork"
      source_port_range          = "*"
      destination_address_prefix = "SQL"
      destination_port_range     = "1433"
    }
    Out-KeyVault-443 = {
      name                       = "Out-KeyVault-443"
      direction                  = "Outbound"
      access                     = "Allow"
      priority                   = 120
      protocol                   = "Tcp"
      source_address_prefix      = "VirtualNetwork"
      source_port_range          = "*"
      destination_address_prefix = "AzureKeyVault"
      destination_port_range     = "443"
    }
    Out-Monitor-1886-443 = {
      name                       = "Out-Monitor-1886-443"
      direction                  = "Outbound"
      access                     = "Allow"
      priority                   = 130
      protocol                   = "Tcp"
      source_address_prefix      = "VirtualNetwork"
      source_port_range          = "*"
      destination_address_prefix = "AzureMonitor"
      destination_port_ranges    = ["443", "1886"]
    }
    Out-Internet-80 = {
      name                       = "Out-Internet-80"
      direction                  = "Outbound"
      access                     = "Allow"
      priority                   = 140
      protocol                   = "Tcp"
      source_address_prefix      = "VirtualNetwork"
      source_port_range          = "*"
      destination_address_prefix = "Internet"
      destination_port_range     = "80"
    }
  }

  enable_telemetry = false
}

# ---- Networking: VNet + subnets (AVM) ---------------------------------------
module "network" {
  count   = var.deploy_virtual_network ? 1 : 0
  source  = "Azure/avm-res-network-virtualnetwork/azurerm"
  version = "0.22.1"

  name          = "${local.name_prefix}-vnet"
  location      = var.location
  parent_id     = local.rg_id
  address_space = ["10.20.0.0/16"]
  tags          = local.tags

  subnets = {
    apim = {
      name           = "apim"
      address_prefix = "10.20.0.0/24"
      # Classic APIM injection subnet must NOT be delegated.
      network_security_group = {
        id = module.apim_nsg[0].resource_id
      }
    }
    privatelink = {
      name                              = "privatelink"
      address_prefix                    = "10.20.1.0/24"
      private_endpoint_network_policies = "Disabled"
    }
  }

  enable_telemetry = false
}

# ---- Networking: Redis private DNS zone + VNet link (AVM) --------------------
module "redis_dns" {
  count   = var.deploy_virtual_network && var.deploy_private_dns ? 1 : 0
  source  = "Azure/avm-res-network-privatednszone/azurerm"
  version = "0.5.0"

  domain_name = "privatelink.redis.azure.net"
  parent_id   = local.rg_id
  tags        = local.tags

  virtual_network_links = {
    redis = {
      vnetlinkname         = "${local.name_prefix}-redis-dns-link"
      vnetid               = module.network[0].resource_id
      registration_enabled = false
    }
  }

  enable_telemetry = false
}

# ---- Redis Enterprise (AVM) -------------------------------------------------
# Database (name "default", RediSearch, EnterpriseCluster, port 10000) is created
# inline by the module. The private endpoint is folded into private_endpoints.
# Redis Enterprise cache names must be globally unique across Azure, so a random
# suffix is appended (mirrors the random_string.kv_suffix pattern for Key Vault).
resource "random_string" "redis_suffix" {
  count   = var.deploy_redis ? 1 : 0
  length  = 6
  special = false
  upper   = false
  numeric = true
}

module "redis" {
  count   = var.deploy_redis ? 1 : 0
  source  = "Azure/avm-res-cache-redisenterprise/azurerm"
  version = "0.2.0"

  name             = "${local.name_prefix}-redis-${random_string.redis_suffix[0].result}"
  location         = var.redis_location
  parent_id        = local.rg_id
  tags             = local.tags
  sku_name         = var.redis_sku
  enable_telemetry = false

  minimum_tls_version   = "1.2"
  high_availability     = var.redis_high_availability
  public_network_access = "Disabled"

  clustering_policy = "EnterpriseCluster"
  eviction_policy   = "NoEviction"
  redis_modules = [
    { name = "RediSearch" }
  ]

  # Private endpoint (PE lives in the VNet region; Redis may be cross-region).
  private_endpoints = var.deploy_private_endpoints ? {
    redis = {
      name                            = "${local.name_prefix}-redis-pe"
      location                        = var.location
      subnet_resource_id              = local.private_link_subnet_id
      private_dns_zone_resource_ids   = local.redis_dns_zone_id != null ? [local.redis_dns_zone_id] : []
      private_service_connection_name = "${local.name_prefix}-redis-plsc"
    }
  } : {}
}

# The AVM redisenterprise module does not expose accessKeysAuthentication and
# the ARM default for API 2025-07-01 is "Disabled". APIM's external cache is
# wired with a connection string built from listKeys, which fails while keys
# are disabled. Patch the setting back on after the module creates the database.
resource "azapi_update_resource" "redis_access_keys" {
  count       = var.deploy_redis ? 1 : 0
  type        = "Microsoft.Cache/redisEnterprise/databases@2025-07-01"
  resource_id = module.redis[0].database_id

  body = {
    properties = {
      accessKeysAuthentication = "Enabled"
    }
  }
}

# ---- Content Safety (optional) — AVM cognitive account ----------------------
module "content_safety" {
  count   = local.content_safety_effective ? 1 : 0
  source  = "Azure/avm-res-cognitiveservices-account/azurerm"
  version = "0.11.1"

  kind                          = "ContentSafety"
  name                          = "${local.name_prefix}-safety"
  location                      = var.location
  parent_id                     = local.rg_id
  sku_name                      = "S0"
  custom_subdomain_name         = "${local.name_prefix}-safety"
  public_network_access_enabled = true
  local_auth_enabled            = false # tenant enforces Entra-only auth; listKeys is blocked
  tags                          = local.tags
  enable_telemetry              = false
}

# ---- Azure OpenAI: primary + secondary — AVM cognitive accounts -------------
module "openai_primary" {
  count   = var.deploy_primary_azure_openai ? 1 : 0
  source  = "Azure/avm-res-cognitiveservices-account/azurerm"
  version = "0.11.1"

  kind                          = "OpenAI"
  name                          = "${local.name_prefix}-aoai-primary"
  location                      = var.location
  parent_id                     = local.rg_id
  sku_name                      = "S0"
  custom_subdomain_name         = "${local.name_prefix}-aoai-primary"
  public_network_access_enabled = true
  local_auth_enabled            = false # tenant enforces Entra-only auth; listKeys is blocked
  tags                          = local.tags
  enable_telemetry              = false

  cognitive_deployments = {
    for d in var.primary_deployments : d.deployment_name => {
      name                   = d.deployment_name
      rai_policy_name        = "Microsoft.DefaultV2"
      version_upgrade_option = "OnceNewDefaultVersionAvailable"
      model = {
        format  = "OpenAI"
        name    = d.model_name
        version = d.model_version
      }
      scale = {
        type     = d.sku_name
        capacity = d.capacity
      }
    }
  }
}

module "openai_secondary" {
  count   = var.deploy_secondary_azure_openai ? 1 : 0
  source  = "Azure/avm-res-cognitiveservices-account/azurerm"
  version = "0.11.1"

  kind                          = "OpenAI"
  name                          = "${local.name_prefix}-aoai-secondary"
  location                      = var.secondary_location
  parent_id                     = local.rg_id
  sku_name                      = "S0"
  custom_subdomain_name         = "${local.name_prefix}-aoai-secondary"
  public_network_access_enabled = true
  local_auth_enabled            = false # tenant enforces Entra-only auth; listKeys is blocked
  tags                          = local.tags
  enable_telemetry              = false

  cognitive_deployments = {
    for d in var.secondary_deployments : d.deployment_name => {
      name                   = d.deployment_name
      rai_policy_name        = "Microsoft.DefaultV2"
      version_upgrade_option = "OnceNewDefaultVersionAvailable"
      model = {
        format  = "OpenAI"
        name    = d.model_name
        version = d.model_version
      }
      scale = {
        type     = d.sku_name
        capacity = d.capacity
      }
    }
  }
}

module "foundry_primary" {
  count  = var.deploy_foundry ? 1 : 0
  source = "./modules/foundry"

  location            = var.location
  resource_group_name = local.rg_name
  resource_group_id   = local.rg_id
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
  resource_group_id   = local.rg_id
  name_prefix         = local.name_prefix
  tags                = local.tags
  project_name        = var.foundry_project_name
  site                = "secondary"
  # Prior westus2 account left a soft-deleted shell holding the default
  # subdomain; suffix avoids the reserved name.
  account_name_suffix = "-e2"
  model_deployments   = concat(var.foundry_model_deployments, local.foundry_optional_model_deployments)
}

# ---- APIM service (AVM) -----------------------------------------------------
# Developer SKU is forced to capacity 1 (parity with Bicep).
module "apim" {
  count   = var.deploy_apim ? 1 : 0
  source  = "Azure/avm-res-apimanagement-service/azurerm"
  version = "0.9.0"

  name                = "${local.name_prefix}-apim"
  location            = var.location
  resource_group_name = local.rg_name
  tags                = local.tags
  publisher_email     = var.publisher_email
  publisher_name      = var.publisher_name
  sku_name            = "${var.apim_sku}_${var.apim_sku == "Developer" ? 1 : var.apim_sku_capacity}"

  managed_identities = {
    system_assigned = true
  }

  virtual_network_type      = local.apim_virtual_network_type
  virtual_network_subnet_id = local.apim_virtual_network_type == "None" ? null : local.apim_subnet_id

  # Diagnostic settings to Log Analytics (AVM interface).
  diagnostic_settings = var.deploy_diagnostic_settings && local.log_analytics_id != null ? {
    apim = {
      name                  = "apim-diagnostics"
      workspace_resource_id = local.log_analytics_id
      log_groups            = ["allLogs"]
      metric_categories     = ["AllMetrics"]
    }
  } : {}

  enable_telemetry = false
}

# ---- APIM App Insights logger + diagnostic (azurerm — no AVM interface) ------
# The APIM AVM module (0.9.0) exposes no App Insights logger/diagnostic input,
# so these remain native azurerm resources bound to the AVM-created service.
resource "azurerm_api_management_logger" "appinsights" {
  count               = var.deploy_apim ? 1 : 0
  name                = "appinsights-logger"
  api_management_name = module.apim[0].name
  resource_group_name = local.rg_name
  resource_id         = try(module.app_insights[0].resource_id, null)

  application_insights {
    instrumentation_key = try(module.app_insights[0].instrumentation_key, null)
  }
}

resource "azurerm_api_management_diagnostic" "appinsights" {
  count                    = var.deploy_apim ? 1 : 0
  identifier               = "applicationinsights"
  api_management_name      = module.apim[0].name
  resource_group_name      = local.rg_name
  api_management_logger_id = azurerm_api_management_logger.appinsights[0].id

  always_log_errors         = true
  verbosity                 = "verbose"
  http_correlation_protocol = "W3C"
  log_client_ip             = true
  sampling_percentage       = 100
}

# ---- APIM control plane (APIs, backends, pool, policies, products, cache) ----
module "apim_config" {
  count  = var.deploy_apim ? 1 : 0
  source = "./modules/apim-config"

  apim_id            = module.apim[0].resource_id
  policy_dir         = "${path.module}/../../apim/policies"
  products_json_path = "${path.module}/../../apim/products/products.json"
  named_values       = local.apim_named_values

  enable_gateway_api            = var.enable_gateway_api
  enable_load_balancing         = var.enable_load_balancing
  enable_semantic_cache         = var.enable_semantic_cache
  enable_content_safety         = local.content_safety_effective
  enable_products               = var.enable_products
  enable_hosted_agent           = var.enable_hosted_agent && var.deploy_foundry
  enable_model_alias_management = var.enable_model_alias_management
  enable_advanced_observability = var.enable_advanced_observability
  deploy_secondary_azure_openai = var.deploy_secondary_azure_openai

  aoai_primary_endpoint      = try(module.openai_primary[0].endpoint, "")
  aoai_secondary_endpoint    = try(module.openai_secondary[0].endpoint, "")
  embeddings_url             = var.enable_semantic_cache ? "${trimsuffix(try(module.openai_primary[0].endpoint, ""), "/")}/openai/deployments/text-embedding-3-small/embeddings" : ""
  content_safety_endpoint    = local.content_safety_effective ? try(module.content_safety[0].endpoint, "") : ""
  foundry_primary_endpoint   = var.deploy_foundry ? try(module.foundry_primary[0].project_endpoint, "") : ""
  foundry_secondary_endpoint = var.deploy_foundry ? try(module.foundry_secondary[0].project_endpoint, "") : ""

  redis_database_id = var.enable_semantic_cache ? try(module.redis[0].database_id, "") : ""
  redis_host_name   = var.enable_semantic_cache ? try(module.redis[0].hostname, "") : ""

  # listKeys inside this module fails unless access keys are re-enabled first.
  depends_on = [azapi_update_resource.redis_access_keys]
}

# ---- Role assignments: APIM identity -> backends ----------------------------
module "role_primary" {
  count  = var.deploy_role_assignments && var.deploy_apim && var.deploy_primary_azure_openai ? 1 : 0
  source = "./modules/role-assignment"

  principal_id       = module.apim[0].resource.identity[0].principal_id
  scope_id           = module.openai_primary[0].resource_id
  role_definition_id = local.role_openai_user
}

module "role_secondary" {
  count  = var.deploy_role_assignments && var.deploy_apim && var.deploy_secondary_azure_openai ? 1 : 0
  source = "./modules/role-assignment"

  principal_id       = module.apim[0].resource.identity[0].principal_id
  scope_id           = module.openai_secondary[0].resource_id
  role_definition_id = local.role_openai_user
}

module "role_content_safety" {
  count  = var.deploy_role_assignments && var.deploy_apim && local.content_safety_effective ? 1 : 0
  source = "./modules/role-assignment"

  principal_id       = module.apim[0].resource.identity[0].principal_id
  scope_id           = module.content_safety[0].resource_id
  role_definition_id = local.role_cognitive_services_user
}

module "role_foundry_primary_account" {
  count              = var.deploy_role_assignments && var.deploy_apim && var.deploy_foundry ? 1 : 0
  source             = "./modules/role-assignment"
  principal_id       = module.apim[0].resource.identity[0].principal_id
  scope_id           = module.foundry_primary[0].account_id
  role_definition_id = local.role_foundry_account_owner
}

module "role_foundry_primary_project_owner" {
  count              = var.deploy_role_assignments && var.deploy_apim && var.deploy_foundry ? 1 : 0
  source             = "./modules/role-assignment"
  principal_id       = module.apim[0].resource.identity[0].principal_id
  scope_id           = module.foundry_primary[0].project_id
  role_definition_id = local.role_foundry_account_owner
}

module "role_foundry_primary_agent_consumer" {
  count              = var.deploy_role_assignments && var.deploy_apim && var.deploy_foundry ? 1 : 0
  source             = "./modules/role-assignment"
  principal_id       = module.apim[0].resource.identity[0].principal_id
  scope_id           = module.foundry_primary[0].project_id
  role_definition_id = local.role_foundry_agent_consumer
}

module "role_foundry_secondary_account" {
  count              = var.deploy_role_assignments && var.deploy_apim && var.deploy_foundry ? 1 : 0
  source             = "./modules/role-assignment"
  principal_id       = module.apim[0].resource.identity[0].principal_id
  scope_id           = module.foundry_secondary[0].account_id
  role_definition_id = local.role_foundry_account_owner
}

module "role_foundry_secondary_project_owner" {
  count              = var.deploy_role_assignments && var.deploy_apim && var.deploy_foundry ? 1 : 0
  source             = "./modules/role-assignment"
  principal_id       = module.apim[0].resource.identity[0].principal_id
  scope_id           = module.foundry_secondary[0].project_id
  role_definition_id = local.role_foundry_account_owner
}

module "role_foundry_secondary_agent_consumer" {
  count              = var.deploy_role_assignments && var.deploy_apim && var.deploy_foundry ? 1 : 0
  source             = "./modules/role-assignment"
  principal_id       = module.apim[0].resource.identity[0].principal_id
  scope_id           = module.foundry_secondary[0].project_id
  role_definition_id = local.role_foundry_agent_consumer
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
