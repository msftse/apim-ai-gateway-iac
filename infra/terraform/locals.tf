# =============================================================================
# Derived values, effective toggles, and cross-variable dependency validations.
# =============================================================================

locals {
  name_prefix = "${var.resource_prefix}-${var.environment_name}"

  base_tags = {
    project     = "enterprise-ai-gateway-poc"
    environment = var.environment_name
    managedBy   = "terraform"
  }
  tags = merge(local.base_tags, var.tags)

  # Effective content safety: the capability flag AND the deploy toggle. The
  # legacy content_safety_enabled is AND-ed in for back-compat (default true).
  content_safety_effective = var.enable_content_safety && var.content_safety_enabled && var.deploy_content_safety

  # Resource group name/id resolution (create vs reuse existing).
  resource_group_name = var.deploy_resource_group ? "${local.name_prefix}-rg" : var.existing_resource_group_name

  # Networking id resolution.
  apim_subnet_id         = var.deploy_virtual_network ? try(module.network[0].apim_subnet_id, null) : (var.existing_apim_subnet_id != "" ? var.existing_apim_subnet_id : null)
  private_link_subnet_id = var.deploy_virtual_network ? try(module.network[0].private_link_subnet_id, null) : (var.existing_private_link_subnet_id != "" ? var.existing_private_link_subnet_id : null)
  redis_dns_zone_id      = var.deploy_virtual_network || var.deploy_private_dns ? try(module.network[0].redis_dns_zone_id, null) : (var.existing_redis_dns_zone_id != "" ? var.existing_redis_dns_zone_id : null)

  # Log Analytics id resolution.
  log_analytics_id = var.deploy_log_analytics ? try(module.monitoring[0].log_analytics_id, null) : (var.existing_log_analytics_workspace_id != "" ? var.existing_log_analytics_workspace_id : null)

  # APIM VNet injection: External when a VNet/subnet is available, else None.
  apim_virtual_network_type = local.apim_subnet_id != null ? "External" : "None"

  # Named values seeded into APIM (non-secret). This is the SINGLE source of
  # truth (replaces apim/named-values/named-values.json + configure-apim.sh).
  # Runtime endpoints resolve via try() so a skipped component never breaks plan.
  apim_named_values = merge(
    # ---- Core endpoints + routing (always) ----
    {
      "aoai-primary-endpoint"      = try(module.openai_primary[0].endpoint, "")
      "aoai-secondary-endpoint"    = try(module.openai_secondary[0].endpoint, "")
      "aoai-embeddings-url"        = var.enable_semantic_cache ? "${trimsuffix(try(module.openai_primary[0].endpoint, ""), "/")}/openai/deployments/text-embedding-3-small/embeddings" : ""
      "aoai-api-version"           = "2024-10-21"
      "alias-map-json"             = var.enable_model_alias_management ? jsonencode(var.alias_map) : "{}"
      "aoai-pool-backend-id"       = "aoai-pool"
      "aoai-primary-backend-id"    = "aoai-primary"
      "aoai-secondary-backend-id"  = "aoai-secondary"
      "embeddings-backend-id"      = "embeddings-backend"
      "content-safety-backend-id"  = "content-safety-backend"
      "content-safety-on"          = local.content_safety_effective ? "true" : "false"
      "content-safety-endpoint"    = local.content_safety_effective ? try(module.content_safety[0].endpoint, "") : ""
      "content-safety-threshold"   = "4"
      "semantic-cache-threshold"   = var.semantic_cache_threshold
      "semantic-cache-ttl-seconds" = "3600"
      "max-body-bytes"             = "32768"
      "prompt-logging-enabled"     = "false"
      "llm-metrics-namespace"      = var.enable_advanced_observability ? "EnterpriseAIGateway" : ""
      "web-allowed-origin"         = try("https://${module.apps[0].web_fqdn}", "")
      "entra-authority"            = "https://login.microsoftonline.com/"
      "entra-audience"             = "api://${local.name_prefix}-apim"
      "tenant-id"                  = data.azurerm_client_config.current.tenant_id
      "foundry-primary-endpoint"   = var.deploy_foundry ? try(module.foundry_primary[0].project_endpoint, "") : ""
      "foundry-secondary-endpoint" = var.deploy_foundry ? try(module.foundry_secondary[0].project_endpoint, "") : ""
    },
    # ---- Per-tier token limits (enable_token_limits) ----
    var.enable_token_limits ? {
      "token-tpm-free"             = "1000"
      "token-quota-free-daily"     = "20000"
      "max-completion-free"        = "256"
      "token-tpm-standard"         = "10000"
      "token-quota-standard-daily" = "500000"
      "max-completion-standard"    = "1024"
      "token-tpm-premium"          = "60000"
      "token-quota-premium-daily"  = "5000000"
      "max-completion-premium"     = "4096"
    } : {},
    # ---- MCP web-search (enable_mcp_web_search) ----
    var.enable_mcp_governance && var.enable_mcp_web_search ? {
      "web-search-backend-url" = try(module.search_mcp[0].search_backend_url, "")
      "web-search-backend-id"  = "web-search-backend"
      "mcp-server-name"        = "web-search-mcp"
      "mcp-server-path"        = "web-search-mcp"
      "mcp-tool-name"          = "searchWeb"
    } : {}
  )
}

data "azurerm_client_config" "current" {}

# ---- Dependency validations (Part 4) ----------------------------------------
# Fail fast on incompatible combinations with actionable messages.
resource "null_resource" "dependency_validations" {
  # count = 1 so the preconditions below actually evaluate during plan and fail
  # fast on incompatible combinations. It creates no cloud resource.

  lifecycle {
    precondition {
      condition     = var.deploy_resource_group || var.existing_resource_group_name != ""
      error_message = "deploy_resource_group = false requires existing_resource_group_name to be set."
    }
    precondition {
      condition     = var.deploy_log_analytics || var.existing_log_analytics_workspace_id != ""
      error_message = "deploy_log_analytics = false requires existing_log_analytics_workspace_id (Application Insights and APIM diagnostics depend on it)."
    }
    precondition {
      # APIM diagnostic settings need a workspace (created or existing).
      condition     = !(var.deploy_diagnostic_settings && var.deploy_apim) || local.log_analytics_id != null
      error_message = "deploy_diagnostic_settings for APIM requires a Log Analytics workspace: enable deploy_log_analytics or set existing_log_analytics_workspace_id."
    }
    precondition {
      # Container Apps stream logs to Log Analytics.
      condition     = !var.deploy_apps || var.deploy_log_analytics
      error_message = "deploy_apps requires deploy_log_analytics = true (Container Apps environment streams logs to the workspace via its shared key)."
    }
    precondition {
      # Application Insights is workspace-based.
      condition     = !var.deploy_application_insights || local.log_analytics_id != null
      error_message = "deploy_application_insights requires a Log Analytics workspace (workspace-based App Insights)."
    }
    precondition {
      # APIM logger needs App Insights.
      condition     = !var.deploy_apim || var.deploy_application_insights
      error_message = "deploy_apim requires deploy_application_insights = true (the APIM logger + diagnostic bind to App Insights)."
    }
    precondition {
      # Redis private endpoint needs a subnet + DNS zone.
      condition     = !(var.deploy_redis && var.deploy_private_endpoints) || (local.private_link_subnet_id != null && local.redis_dns_zone_id != null)
      error_message = "The Redis private endpoint requires a private-link subnet and the Redis private DNS zone. Enable deploy_virtual_network + deploy_private_dns, or supply existing_private_link_subnet_id + existing_redis_dns_zone_id."
    }
    precondition {
      # Role assignments need APIM identity + at least one target.
      condition     = !var.deploy_role_assignments || var.deploy_apim
      error_message = "deploy_role_assignments requires deploy_apim = true (assignments grant the APIM managed identity access to backends)."
    }
    precondition {
      condition     = !var.deploy_apim || (var.deploy_primary_azure_openai || var.deploy_secondary_azure_openai)
      error_message = "deploy_apim expects at least one Azure OpenAI backend (deploy_primary_azure_openai or deploy_secondary_azure_openai)."
    }
    precondition {
      condition     = !var.enable_foundry_claude || (trimspace(var.foundry_claude_organization_name) != "" && length(var.foundry_claude_country_code) == 2)
      error_message = "enable_foundry_claude requires foundry_claude_organization_name and a two-letter foundry_claude_country_code."
    }
    precondition {
      condition     = !var.deploy_workbook || local.log_analytics_id != null
      error_message = "deploy_workbook requires a Log Analytics workspace (the workbook queries it)."
    }
    # ---- Capability-flag dependencies -----------------------------------------
    precondition {
      condition     = !var.enable_gateway_api || var.deploy_apim
      error_message = "enable_gateway_api requires deploy_apim = true (the ai-gateway API is created on the APIM service)."
    }
    precondition {
      condition     = !var.enable_gateway_api || var.enable_model_alias_management
      error_message = "enable_gateway_api requires enable_model_alias_management because its policy resolves logical models through alias-map-json."
    }
    precondition {
      condition     = !var.enable_advanced_observability || !var.enable_gateway_api || var.deploy_application_insights
      error_message = "enable_advanced_observability requires deploy_application_insights = true when the gateway API is enabled."
    }
    precondition {
      condition     = !var.enable_a2a_governance
      error_message = "enable_a2a_governance cannot be enabled until a supported A2A backend/API is configured; this POC intentionally does not simulate A2A traffic."
    }
    precondition {
      condition     = !var.enable_semantic_cache || var.deploy_redis
      error_message = "enable_semantic_cache requires deploy_redis = true (the APIM external cache binds to Azure Managed Redis)."
    }
    precondition {
      condition     = !var.enable_load_balancing || var.deploy_primary_azure_openai
      error_message = "enable_load_balancing requires deploy_primary_azure_openai = true (the aoai-pool needs at least the primary backend)."
    }
    precondition {
      condition     = !var.enable_hosted_agent || var.deploy_foundry
      error_message = "enable_hosted_agent requires deploy_foundry = true (the hosted-agent API routes to Foundry project endpoints)."
    }
  }
}
