# =============================================================================
# apim-config — the full APIM control plane as code: named values, policy
# fragments, APIs and operations, backends, load-balanced pool, products, and
# the external Redis cache binding. Everything is applied via azapi against the
# management-API shapes, so a single `terraform apply` produces a fully working
# gateway.
# =============================================================================

# ---- Inputs -----------------------------------------------------------------
variable "apim_id" { type = string }
variable "policy_dir" {
  description = "Absolute path to the apim/policies directory."
  type        = string
}
variable "products_json_path" {
  description = "Absolute path to apim/products/products.json."
  type        = string
}
variable "named_values" {
  description = "Map of APIM named value name => value (non-secret)."
  type        = map(string)
  default     = {}
}

# Capability flags (mirrors root enable_*).
variable "enable_gateway_api" { type = bool }
variable "enable_load_balancing" { type = bool }
variable "enable_semantic_cache" { type = bool }
variable "enable_content_safety" { type = bool }
variable "enable_products" { type = bool }
variable "enable_hosted_agent" { type = bool }
variable "enable_model_alias_management" { type = bool }
variable "enable_advanced_observability" { type = bool }
variable "deploy_secondary_azure_openai" { type = bool }

# Backend URLs (empty string when the matching component is disabled).
variable "aoai_primary_endpoint" {
  type    = string
  default = ""
}
variable "aoai_secondary_endpoint" {
  type    = string
  default = ""
}
variable "embeddings_url" {
  type    = string
  default = ""
}
variable "content_safety_endpoint" {
  type    = string
  default = ""
}
variable "foundry_primary_endpoint" {
  type    = string
  default = ""
}
variable "foundry_secondary_endpoint" {
  type    = string
  default = ""
}

# Redis (for external cache binding). Empty when semantic cache disabled.
variable "redis_database_id" {
  type    = string
  default = ""
}
variable "redis_host_name" {
  type    = string
  default = ""
}

# =============================================================================
# Locals — API version pins + derived collections.
# =============================================================================
locals {
  api_version = "2024-05-01"
  # Derived from apim_id (.../resourceGroups/<rg>/providers/Microsoft.ApiManagement/service/<name>)
  apim_name    = element(split("/", var.apim_id), length(split("/", var.apim_id)) - 1)
  apim_rg_name = element(split("/", var.apim_id), 4)

  # Fragments are needed by both the gateway and agent composed policies.
  want_fragments = var.enable_gateway_api || var.enable_hosted_agent

  # fragment-id => file path (relative to policy_dir). Mirrors the FRAGMENTS
  # list in configure-apim.sh.
  fragment_files = {
    "ai-correlation-id"         = "shared/fragments/correlation-id.xml"
    "ai-jwt-validation"         = "model/fragments/jwt-validation.xml"
    "ai-consumer-context"       = "shared/fragments/consumer-context.xml"
    "ai-request-validation"     = "model/fragments/request-validation.xml"
    "ai-model-alias-resolution" = "model/fragments/model-alias-resolution.xml"
    "ai-token-limit"            = "shared/fragments/token-limit.xml"
    "ai-content-safety"         = "shared/fragments/content-safety.xml"
    "ai-semantic-cache-lookup"  = "shared/fragments/semantic-cache-lookup.xml"
    "ai-semantic-cache-store"   = "shared/fragments/semantic-cache-store.xml"
    "ai-backend-routing"        = "model/fragments/backend-routing.xml"
    "ai-token-metrics"          = "shared/fragments/token-metrics.xml"
    "ai-structured-logging"     = "shared/fragments/structured-logging.xml"
  }
  fragments = local.want_fragments ? local.fragment_files : {}

  # Circuit-breaker rule shared by AOAI + agent primary backends.
  cb_rule = {
    count            = 3
    interval         = "PT1M"
    statusCodeRanges = [{ min = 429, max = 429 }, { min = 500, max = 599 }]
    tripDuration     = "PT1M"
    acceptRetryAfter = true
  }

  # Single (non-pool) backends: name => { url, breaker(name|null), enabled }.
  single_backends = {
    "aoai-primary" = {
      url     = var.aoai_primary_endpoint
      breaker = "primary-breaker"
      enabled = var.enable_load_balancing && var.aoai_primary_endpoint != ""
    }
    "aoai-secondary" = {
      url     = var.aoai_secondary_endpoint
      breaker = null
      enabled = var.enable_load_balancing && var.deploy_secondary_azure_openai && var.aoai_secondary_endpoint != ""
    }
    "embeddings-backend" = {
      url     = var.embeddings_url
      breaker = null
      enabled = var.enable_semantic_cache && var.embeddings_url != ""
    }
    "content-safety-backend" = {
      url     = var.content_safety_endpoint
      breaker = null
      enabled = var.enable_content_safety && var.content_safety_endpoint != ""
    }
    "agent-free-primary" = {
      url     = var.foundry_primary_endpoint
      breaker = "free-primary-breaker"
      enabled = var.enable_hosted_agent && var.foundry_primary_endpoint != ""
    }
    "agent-free-secondary" = {
      url     = var.foundry_secondary_endpoint
      breaker = null
      enabled = var.enable_hosted_agent && var.foundry_secondary_endpoint != ""
    }
    "agent-standard-primary" = {
      url     = var.foundry_primary_endpoint
      breaker = "standard-primary-breaker"
      enabled = var.enable_hosted_agent && var.foundry_primary_endpoint != ""
    }
    "agent-standard-secondary" = {
      url     = var.foundry_secondary_endpoint
      breaker = null
      enabled = var.enable_hosted_agent && var.foundry_secondary_endpoint != ""
    }
    "agent-premium-primary" = {
      url     = var.foundry_primary_endpoint
      breaker = "premium-primary-breaker"
      enabled = var.enable_hosted_agent && var.foundry_primary_endpoint != ""
    }
    "agent-premium-secondary" = {
      url     = var.foundry_secondary_endpoint
      breaker = null
      enabled = var.enable_hosted_agent && var.foundry_secondary_endpoint != ""
    }
  }
  enabled_single_backends = { for k, v in local.single_backends : k => v if v.enabled }

  # Products (parity with apim/products/products.json).
  products = var.enable_products ? {
    free     = "Free"
    standard = "Standard"
    premium  = "Premium"
  } : {}

  # APIs to bind to products: always ai-gateway; +hosted-agent.
  product_apis = compact([
    var.enable_gateway_api ? "ai-gateway" : "",
    var.enable_hosted_agent ? "hosted-agent" : "",
  ])
  # Flattened product x api bindings.
  product_api_bindings = merge([
    for pid, _ in local.products : {
      for api in local.product_apis : "${pid}|${api}" => { product = pid, api = api }
    }
  ]...)
}

# =============================================================================
# Named values — single source of truth for APIM NVs.
# =============================================================================
resource "azapi_resource" "named_value" {
  for_each  = var.named_values
  type      = "Microsoft.ApiManagement/service/namedValues@${local.api_version}"
  name      = each.key
  parent_id = var.apim_id
  body = {
    properties = {
      displayName = each.key
      value       = each.value
      secret      = false
    }
  }
}

# =============================================================================
# Backends (Single) + circuit breakers.
# =============================================================================
resource "azapi_resource" "backend" {
  for_each  = local.enabled_single_backends
  type      = "Microsoft.ApiManagement/service/backends@${local.api_version}"
  name      = each.key
  parent_id = var.apim_id
  body = {
    properties = merge(
      {
        url      = each.value.url
        protocol = "http"
      },
      each.value.breaker == null ? {} : {
        circuitBreaker = {
          rules = [
            {
              name             = each.value.breaker
              failureCondition = { count = local.cb_rule.count, interval = local.cb_rule.interval, statusCodeRanges = local.cb_rule.statusCodeRanges }
              tripDuration     = local.cb_rule.tripDuration
              acceptRetryAfter = local.cb_rule.acceptRetryAfter
            }
          ]
        }
      }
    )
  }
}

# Priority-based load-balanced pool (primary p1, secondary p2 -> failover).
resource "azapi_resource" "aoai_pool" {
  count     = var.enable_load_balancing && var.aoai_primary_endpoint != "" ? 1 : 0
  type      = "Microsoft.ApiManagement/service/backends@${local.api_version}"
  name      = "aoai-pool"
  parent_id = var.apim_id
  body = {
    properties = {
      type = "Pool"
      pool = {
        services = concat(
          [{ id = "${var.apim_id}/backends/aoai-primary", priority = 1, weight = 1 }],
          var.deploy_secondary_azure_openai && var.aoai_secondary_endpoint != "" ? [{ id = "${var.apim_id}/backends/aoai-secondary", priority = 2, weight = 1 }] : []
        )
      }
    }
  }
  depends_on = [azapi_resource.backend]
}

# =============================================================================
# Policy fragments (rawxml). Depend on named values (policies reference {{..}}).
# =============================================================================
resource "azapi_resource" "policy_fragment" {
  for_each  = local.fragments
  type      = "Microsoft.ApiManagement/service/policyFragments@${local.api_version}"
  name      = each.key
  parent_id = var.apim_id
  body = {
    properties = {
      format = "rawxml"
      value  = file("${var.policy_dir}/${each.value}")
    }
  }
  depends_on = [azapi_resource.named_value]
}

# =============================================================================
# ai-gateway API (LLM passthrough) + operation + composed policy.
# =============================================================================
resource "azapi_resource" "gateway_api" {
  count     = var.enable_gateway_api ? 1 : 0
  type      = "Microsoft.ApiManagement/service/apis@${local.api_version}"
  name      = "ai-gateway"
  parent_id = var.apim_id
  body = {
    properties = {
      displayName          = "Enterprise AI Gateway"
      path                 = "ai"
      protocols            = ["https"]
      subscriptionRequired = true
    }
  }
}

resource "azapi_resource" "gateway_operation" {
  count     = var.enable_gateway_api ? 1 : 0
  type      = "Microsoft.ApiManagement/service/apis/operations@${local.api_version}"
  name      = "chat-completions"
  parent_id = azapi_resource.gateway_api[0].id
  body = {
    properties = {
      displayName = "Chat Completions"
      method      = "POST"
      urlTemplate = "/deployments/{deployment-id}/chat/completions"
      templateParameters = [
        { name = "deployment-id", type = "string", required = true }
      ]
    }
  }
}

resource "azapi_resource" "gateway_policy" {
  count     = var.enable_gateway_api ? 1 : 0
  type      = "Microsoft.ApiManagement/service/apis/policies@${local.api_version}"
  name      = "policy"
  parent_id = azapi_resource.gateway_api[0].id
  body = {
    properties = {
      format = "rawxml"
      value  = file("${var.policy_dir}/model/api-policy.xml")
    }
  }
  depends_on = [
    azapi_resource.gateway_operation,
    azapi_resource.policy_fragment,
    azapi_resource.backend,
    azapi_resource.aoai_pool,
  ]
}

# =============================================================================
# Hosted-agent API (Foundry responses) + operation + policy.
# =============================================================================
resource "azapi_resource" "agent_api" {
  count     = var.enable_hosted_agent ? 1 : 0
  type      = "Microsoft.ApiManagement/service/apis@${local.api_version}"
  name      = "hosted-agent"
  parent_id = var.apim_id
  body = {
    properties = {
      displayName          = "Foundry Hosted Agent"
      path                 = "agent"
      protocols            = ["https"]
      subscriptionRequired = true
    }
  }
}

resource "azapi_resource" "agent_operation" {
  count     = var.enable_hosted_agent ? 1 : 0
  type      = "Microsoft.ApiManagement/service/apis/operations@${local.api_version}"
  name      = "responses"
  parent_id = azapi_resource.agent_api[0].id
  body = {
    properties = {
      displayName = "Responses"
      method      = "POST"
      urlTemplate = "/v1/responses"
    }
  }
}

resource "azapi_resource" "agent_policy" {
  count     = var.enable_hosted_agent ? 1 : 0
  type      = "Microsoft.ApiManagement/service/apis/policies@${local.api_version}"
  name      = "policy"
  parent_id = azapi_resource.agent_api[0].id
  body = {
    properties = {
      format = "rawxml"
      value  = file("${var.policy_dir}/agent/api-policy.xml")
    }
  }
  depends_on = [
    azapi_resource.agent_operation,
    azapi_resource.policy_fragment,
    azapi_resource.backend,
  ]
}

# =============================================================================
# Products (free/standard/premium) + API bindings.
# =============================================================================
resource "azapi_resource" "product" {
  for_each  = local.products
  type      = "Microsoft.ApiManagement/service/products@${local.api_version}"
  name      = each.key
  parent_id = var.apim_id
  body = {
    properties = {
      displayName          = each.value
      description          = "${each.value} tier."
      subscriptionRequired = true
      approvalRequired     = false
      state                = "published"
    }
  }
}

resource "azurerm_api_management_product_api" "product_api" {
  for_each            = local.product_api_bindings
  product_id          = each.value.product
  api_name            = each.value.api
  api_management_name = local.apim_name
  resource_group_name = local.apim_rg_name
  depends_on = [
    azapi_resource.product,
    azapi_resource.gateway_api,
    azapi_resource.agent_api,
  ]
}

# =============================================================================
# External cache binding to Azure Managed Redis (semantic cache backing store).
# =============================================================================
resource "azapi_resource_action" "redis_keys" {
  count       = var.enable_semantic_cache && var.redis_database_id != "" ? 1 : 0
  type        = "Microsoft.Cache/redisEnterprise/databases@2025-07-01"
  resource_id = var.redis_database_id
  action      = "listKeys"
  method      = "POST"

  response_export_values = ["primaryKey"]
}

resource "azapi_resource" "external_cache" {
  count     = var.enable_semantic_cache && var.redis_database_id != "" ? 1 : 0
  type      = "Microsoft.ApiManagement/service/caches@2022-08-01"
  name      = "default"
  parent_id = var.apim_id
  body = {
    properties = {
      connectionString = "${var.redis_host_name}:10000,password=${azapi_resource_action.redis_keys[0].output.primaryKey},ssl=True,abortConnect=False"
      useFromLocation  = "default"
      description      = var.redis_host_name
    }
  }
}

# ---- Outputs ----------------------------------------------------------------
output "gateway_api_id" { value = try(azapi_resource.gateway_api[0].id, null) }
output "agent_api_id" { value = try(azapi_resource.agent_api[0].id, null) }
