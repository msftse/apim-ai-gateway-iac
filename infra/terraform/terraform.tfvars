# =============================================================================
# APIM AI Gateway — Infrastructure-only deployment.
# Reproduces the live `eaig-demo` gateway (APIM + policies + named values +
# backends + AOAI models + embeddings + Redis semantic cache + Content Safety +
# Foundry hosted agents + monitoring) WITHOUT the web UI (Container Apps) and
# WITHOUT the MCP web-search backend page.
# =============================================================================

# ---- Core -------------------------------------------------------------------
location                 = "westus3"
secondary_location       = "eastus2"
redis_location           = "westus3"
environment_name         = "demo"
resource_prefix          = "eaig"
apim_sku                 = "Developer"
publisher_email          = "ai-platform@contoso.com"
publisher_name           = "Contoso Enterprise AI Platform"
redis_sku                = "Balanced_B0"
content_safety_enabled   = true
networking_mode          = "public"
semantic_cache_threshold = "0.15"

# ---- Capability feature flags (gateway control plane) -----------------------
enable_gateway_api    = true
enable_load_balancing = true
enable_semantic_cache = true
enable_content_safety = true
enable_token_limits   = true
enable_products       = true
enable_hosted_agent   = true

# ---- Excluded: web UI and MCP web-search backend page -----------------------
deploy_apps           = false
enable_mcp_web_search = false
