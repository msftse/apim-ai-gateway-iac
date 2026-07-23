# =============================================================================
# Provider configuration.
# Authentication uses the standard azurerm methods (az CLI, environment vars,
# managed identity, or service principal). No secrets are stored in source.
# subscription_id can be supplied via ARM_SUBSCRIPTION_ID or the variable.
# =============================================================================

provider "azurerm" {
  subscription_id = var.subscription_id != "" ? var.subscription_id : null

  features {
    resource_group {
      # Match Bicep behavior: RG deletion should not be blocked by nested state.
      prevent_deletion_if_contains_resources = false
    }
    key_vault {
      # Purge protection is ON (parity with Bicep), so avoid purge-on-destroy.
      purge_soft_delete_on_destroy       = false
      purge_soft_deleted_keys_on_destroy = false
    }
    cognitive_account {
      purge_soft_delete_on_destroy = false
    }
  }
}

provider "azapi" {}

provider "random" {}
