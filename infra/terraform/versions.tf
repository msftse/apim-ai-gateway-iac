# =============================================================================
# Terraform + provider version constraints.
# azurerm is the primary provider. azapi is used only where azurerm lacks a
# resource/capability (Azure Managed Redis Enterprise 2025-07-01 database
# modules, APIM AI-specific settings, Cognitive Services dynamicThrottling).
# =============================================================================

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    azapi = {
      source  = "azure/azapi"
      version = "~> 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}
