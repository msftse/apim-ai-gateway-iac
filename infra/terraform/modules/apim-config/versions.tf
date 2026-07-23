# apim-config uses azapi exclusively so it can hit the exact APIM management-API
# shapes the post-deploy scripts used (backends+pool, policy fragments, caches,
# MCP servers) — surfaces azurerm does not fully expose.
terraform {
  required_version = ">= 1.6.0"
  required_providers {
    azapi = {
      source  = "azure/azapi"
      version = "~> 2.0"
    }
  }
}
