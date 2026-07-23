# =============================================================================
# Input variables. Mirrors the Bicep parameters (infrastructure/main.bicep and
# module params) and adds:
#   - a deploy_* boolean for EVERY independently-created component (Part 3)
#   - existing_*_id inputs to reuse pre-existing resources (Part 4)
# Dependency validation lives in locals.tf (precondition checks) so a single
# invalid combination fails `terraform plan` with a clear message.
# =============================================================================

# ---- Authentication ---------------------------------------------------------
variable "subscription_id" {
  description = "Azure subscription ID. Falls back to ARM_SUBSCRIPTION_ID / az CLI context when empty."
  type        = string
  default     = ""
}

# ---- Core parameters (parity with main.bicep) -------------------------------
variable "location" {
  description = "Primary location for the resource group and regional resources."
  type        = string
  default     = "westus3"
}

variable "secondary_location" {
  description = "Secondary location for the failover AOAI account (different region from primary)."
  type        = string
  default     = "eastus2"
}

variable "redis_location" {
  description = "Location for Azure Managed Redis (co-located with APIM for lowest cache latency)."
  type        = string
  default     = "westus3"
}

variable "environment_name" {
  description = "Environment name (dev | demo | prod-like)."
  type        = string
  default     = "demo"
}

variable "resource_prefix" {
  description = "Resource naming prefix."
  type        = string
  default     = "eaig"
}

variable "apim_sku" {
  description = "APIM SKU."
  type        = string
  default     = "Developer"
  validation {
    condition     = contains(["Developer", "BasicV2", "StandardV2", "Premium"], var.apim_sku)
    error_message = "apim_sku must be one of: Developer, BasicV2, StandardV2, Premium."
  }
}

variable "apim_sku_capacity" {
  description = "APIM SKU capacity (units). Forced to 1 for Developer."
  type        = number
  default     = 1
}

variable "publisher_email" {
  description = "Publisher email for APIM (required; set to your organization's contact)."
  type        = string
}

variable "publisher_name" {
  description = "Publisher/organization name for APIM (required; set to your organization name)."
  type        = string
}

variable "web_allowed_origin" {
  description = "CORS allowed origin advertised by the gateway/agent APIs (e.g. your web client URL). Must be a single explicit origin because the CORS policy sets allow-credentials=true (wildcard '*' is rejected)."
  type        = string
  default     = "https://localhost"
}

variable "redis_sku" {
  description = "Azure Managed Redis SKU."
  type        = string
  default     = "Balanced_B0"
}

variable "redis_high_availability" {
  description = "Redis high availability (Enabled = primary+replica). Cannot be reversed once Enabled."
  type        = string
  default     = "Enabled"
  validation {
    condition     = contains(["Enabled", "Disabled"], var.redis_high_availability)
    error_message = "redis_high_availability must be Enabled or Disabled."
  }
}

variable "content_safety_enabled" {
  description = "DEPRECATED alias for enable_content_safety. Kept for back-compat; enable_content_safety wins when both are set to non-default. Deploy Azure AI Content Safety (functional feature flag, parity with Bicep contentSafetyEnabled)."
  type        = bool
  default     = true
}

# =============================================================================
# Capability feature flags. Unlike the low-level deploy_* booleans (which gate a
# single component), each enable_* flag turns on a whole CAPABILITY: its Azure
# resources AND the matching APIM control-plane config (APIs, backends, pool,
# policies, products, named values, cache binding). Toggle these in tfvars to
# get a fully working gateway from `terraform apply` alone.
# =============================================================================
variable "enable_gateway_api" {
  description = "Create the ai-gateway API, chat-completions operation, all model/shared policy fragments, and the composed model API policy. This is the core LLM passthrough — without it the gateway has no route."
  type        = bool
  default     = true
}

variable "enable_model_alias_management" {
  description = "Seed and manage the APIM alias-map-json named value used by the model gateway route and the BFF alias-management endpoint."
  type        = bool
  default     = true
}

variable "enable_advanced_observability" {
  description = "Enable AI Gateway token metrics and structured telemetry configuration. Requires deploy_application_insights when the gateway API is enabled."
  type        = bool
  default     = true
}

variable "enable_a2a_governance" {
  description = "Reserve A2A governance configuration. Defaults to false because this POC has no deployed A2A API; enabling it fails explicitly instead of simulating A2A traffic."
  type        = bool
  default     = false
}

variable "enable_load_balancing" {
  description = "Create the aoai-primary/aoai-secondary backends (+circuit breakers) and the aoai-pool priority load-balanced pool used by the backend-routing policy for automatic failover."
  type        = bool
  default     = true
}

variable "enable_semantic_cache" {
  description = "Turn on the APIM semantic cache: requires deploy_redis, creates the embeddings-backend, binds the APIM external cache (caches/default) to Azure Managed Redis, and seeds the cache-related named values consumed by the lookup/store policies."
  type        = bool
  default     = true
}

variable "enable_content_safety" {
  description = "Turn on Azure AI Content Safety end-to-end: the Content Safety account, the content-safety-backend, the content-safety-on named value, and the APIM role assignment. Supersedes content_safety_enabled."
  type        = bool
  default     = true
}

variable "enable_token_limits" {
  description = "Seed the per-tier token TPM / daily-quota / max-completion named values consumed by the ai-token-limit policy fragment."
  type        = bool
  default     = true
}

variable "enable_products" {
  description = "Create the free/standard/premium APIM products and bind them to the enabled APIs."
  type        = bool
  default     = true
}

variable "enable_hosted_agent" {
  description = "Create the hosted-agent APIM API (responses operation + agent policy + agent backends + product bindings). Requires deploy_foundry. The agent CONTAINER image is still published by scripts/deploy-hosted-agent.sh."
  type        = bool
  default     = true
}

variable "networking_mode" {
  description = "Public or private networking mode."
  type        = string
  default     = "public"
  validation {
    condition     = contains(["public", "private"], var.networking_mode)
    error_message = "networking_mode must be public or private."
  }
}

variable "semantic_cache_threshold" {
  description = "Semantic cache vector-distance threshold (0-1). LOWER = stricter match."
  type        = string
  default     = "0.15"
}

variable "log_retention_in_days" {
  description = "Log Analytics retention in days."
  type        = number
  default     = 30
}

# ---- Model deployments (parity with primaryDeployments/secondaryDeployments)-
variable "primary_deployments" {
  description = "Model deployments for the PRIMARY AOAI account. fast/gpt-4o-mini is a regional Standard deployment at low capacity so it returns a real HTTP 429 when TPM is exhausted."
  type = list(object({
    alias           = string
    deployment_name = string
    model_name      = string
    model_version   = string
    capacity        = number
    sku_name        = optional(string, "GlobalStandard")
  }))
  default = [
    { alias = "fast", deployment_name = "gpt-5.4-nano", model_name = "gpt-5.4-nano", model_version = "2026-03-17", capacity = 10 },
    { alias = "balanced", deployment_name = "gpt-5.4-mini", model_name = "gpt-5.4-mini", model_version = "2026-03-17", capacity = 10 },
    { alias = "reasoning", deployment_name = "gpt-5.4", model_name = "gpt-5.4", model_version = "2026-03-05", capacity = 10 },
    { alias = "embeddings", deployment_name = "text-embedding-3-small", model_name = "text-embedding-3-small", model_version = "1", capacity = 50, sku_name = "GlobalStandard" },
  ]
}

variable "secondary_deployments" {
  description = "Model deployments for the SECONDARY AOAI account (failover). fast stays GlobalStandard at higher capacity to absorb failover."
  type = list(object({
    alias           = string
    deployment_name = string
    model_name      = string
    model_version   = string
    capacity        = number
    sku_name        = optional(string, "GlobalStandard")
  }))
  default = [
    { alias = "fast", deployment_name = "gpt-5.4-nano", model_name = "gpt-5.4-nano", model_version = "2026-03-17", capacity = 10 },
    { alias = "balanced", deployment_name = "gpt-5.4-mini", model_name = "gpt-5.4-mini", model_version = "2026-03-17", capacity = 10 },
    { alias = "reasoning", deployment_name = "gpt-5.4", model_name = "gpt-5.4", model_version = "2026-03-05", capacity = 10 },
    { alias = "embeddings", deployment_name = "text-embedding-3-small", model_name = "text-embedding-3-small", model_version = "1", capacity = 50, sku_name = "GlobalStandard" },
  ]
}

variable "alias_map" {
  description = "Logical alias -> AOAI deployment name map, pushed to APIM as the alias-map-json named value so routing changes without code edits."
  type        = map(string)
  default = {
    fast      = "gpt-5.4-nano"
    balanced  = "gpt-5.4-mini"
    reasoning = "gpt-5.4"
  }
}

variable "tags" {
  description = "Extra tags merged onto the base tag set."
  type        = map(string)
  default     = {}
}

# =============================================================================
# Part 3 — per-component deploy_* booleans.
# Every independently-created component has a toggle. Modules/resources use
# count/for_each so disabling one leaves the rest deployable, and outputs use
# try(...) to stay safe when a component is skipped.
# =============================================================================
variable "deploy_resource_group" {
  description = "Create the resource group. Set false to deploy into an existing RG (see existing_resource_group_name)."
  type        = bool
  default     = true
}

variable "deploy_virtual_network" {
  description = "Create the VNet, subnets, and NSG."
  type        = bool
  default     = true
}

variable "deploy_private_endpoints" {
  description = "Create private endpoints (currently the Redis private endpoint)."
  type        = bool
  default     = true
}

variable "deploy_private_dns" {
  description = "Create the private DNS zone(s) and VNet links."
  type        = bool
  default     = true
}

variable "deploy_apim" {
  description = "Create the API Management service (and its logger/diagnostics/named values)."
  type        = bool
  default     = true
}

variable "deploy_primary_azure_openai" {
  description = "Create the primary Azure OpenAI account and its deployments."
  type        = bool
  default     = true
}

variable "deploy_secondary_azure_openai" {
  description = "Create the secondary (failover) Azure OpenAI account and its deployments."
  type        = bool
  default     = true
}

variable "deploy_content_safety" {
  description = "Create the Azure AI Content Safety account. Combined with content_safety_enabled."
  type        = bool
  default     = true
}

variable "deploy_redis" {
  description = "Create the Azure Managed Redis (Redis Enterprise) instance and database."
  type        = bool
  default     = true
}

variable "deploy_key_vault" {
  description = "Create the Key Vault."
  type        = bool
  default     = true
}

variable "deploy_log_analytics" {
  description = "Create the Log Analytics workspace."
  type        = bool
  default     = true
}

variable "deploy_application_insights" {
  description = "Create the Application Insights component."
  type        = bool
  default     = true
}

variable "deploy_workbook" {
  description = "Create the Azure Monitor workbook."
  type        = bool
  default     = true
}

variable "deploy_diagnostic_settings" {
  description = "Create diagnostic settings (APIM -> Log Analytics)."
  type        = bool
  default     = true
}

variable "deploy_role_assignments" {
  description = "Create RBAC role assignments (APIM identity -> AOAI / Content Safety)."
  type        = bool
  default     = true
}

variable "deploy_managed_identities" {
  description = "Create user-assigned managed identities. The POC uses system-assigned identities on APIM/apps, so this is reserved/off by default."
  type        = bool
  default     = false
}

variable "deploy_foundry" {
  description = "Create the Microsoft Foundry account and Azure Container Registry used by the Hosted Agent."
  type        = bool
  default     = true
}

variable "deploy_hosted_agent" {
  description = "Publish the Hosted Agent and configure the separate APIM agent API in the deployment wrapper."
  type        = bool
  default     = true
}

variable "foundry_project_name" {
  description = "Foundry project name used by the Customer Support Hosted Agent."
  type        = string
  default     = "customer-support"
}

variable "foundry_secondary_location" {
  description = "Secondary Azure region for same-tier Hosted Agent failover."
  type        = string
  default     = "westus2"
}

variable "enable_foundry_kimi" {
  description = "Deploy the Azure-sold Moonshot AI Kimi-K2.5 model to each Foundry account."
  type        = bool
  default     = false
}

variable "enable_foundry_llama" {
  description = "Deploy the Azure-sold Meta Llama-3.3-70B-Instruct model to each Foundry account."
  type        = bool
  default     = false
}

variable "enable_foundry_claude" {
  description = "Deploy Anthropic Claude Sonnet 4.6 to each Foundry account. Requires a Claude-eligible subscription and accurate attestation values."
  type        = bool
  default     = false
}

variable "foundry_claude_organization_name" {
  description = "Legal organization name required by Anthropic modelProviderData when enable_foundry_claude is true."
  type        = string
  default     = ""
}

variable "foundry_claude_country_code" {
  description = "Two-letter ISO country code required by Anthropic modelProviderData when enable_foundry_claude is true."
  type        = string
  default     = "US"
}

variable "foundry_claude_industry" {
  description = "Organization industry required by Anthropic modelProviderData when enable_foundry_claude is true."
  type        = string
  default     = "technology"

  validation {
    condition     = contains(["technology", "finance", "healthcare", "education", "retail", "manufacturing", "government", "media", "other"], var.foundry_claude_industry)
    error_message = "foundry_claude_industry must be a supported Anthropic industry value."
  }
}

variable "foundry_model_deployments" {
  description = "Per-tier model deployments created in every Foundry account."
  type = list(object({
    deployment_name = string
    model_name      = string
    model_version   = string
    model_format    = string
    sku_name        = string
    capacity        = number
    model_provider_data = optional(object({
      organization_name = string
      country_code      = string
      industry          = string
    }))
  }))
  default = [
    { deployment_name = "free-model", model_name = "gpt-5.4-nano", model_version = "2026-03-17", model_format = "OpenAI", sku_name = "GlobalStandard", capacity = 10 },
    { deployment_name = "standard-model", model_name = "gpt-5.4-mini", model_version = "2026-03-17", model_format = "OpenAI", sku_name = "GlobalStandard", capacity = 10 },
    { deployment_name = "premium-model", model_name = "gpt-5.4", model_version = "2026-03-05", model_format = "OpenAI", sku_name = "GlobalStandard", capacity = 10 }
  ]
}

# =============================================================================
# Part 4 — existing-resource inputs. When a deploy_* toggle is false, supply the
# corresponding existing resource ID/name so dependents can still wire up.
# =============================================================================
variable "existing_resource_group_name" {
  description = "Name of a pre-existing resource group to use when deploy_resource_group = false."
  type        = string
  default     = ""
}

variable "existing_log_analytics_workspace_id" {
  description = "Resource ID of a pre-existing Log Analytics workspace when deploy_log_analytics = false."
  type        = string
  default     = ""
}

variable "existing_virtual_network_id" {
  description = "Resource ID of a pre-existing VNet when deploy_virtual_network = false."
  type        = string
  default     = ""
}

variable "existing_apim_subnet_id" {
  description = "Subnet ID for APIM injection when deploy_virtual_network = false."
  type        = string
  default     = ""
}

variable "existing_private_link_subnet_id" {
  description = "Subnet ID for private endpoints when deploy_virtual_network = false."
  type        = string
  default     = ""
}

variable "existing_redis_dns_zone_id" {
  description = "Private DNS zone ID (privatelink.redis.azure.net) when deploy_private_dns = false."
  type        = string
  default     = ""
}
