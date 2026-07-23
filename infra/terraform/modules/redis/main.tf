# Azure Managed Redis (Redis Enterprise) — vector store backing the APIM
# semantic cache. Uses azapi to pin api-version 2025-07-01 and set the database
# properties (RediSearch module, accessKeysAuthentication) exactly as the Bicep
# module does; azurerm's redis_enterprise resources do not yet expose the
# 2025-07-01 highAvailability / accessKeysAuthentication surface.
# Parity with infrastructure/modules/redis.bicep.

variable "location" { type = string }
variable "resource_group_id" { type = string }
variable "name_prefix" { type = string }
variable "tags" { type = map(string) }
variable "sku_name" {
  type    = string
  default = "Balanced_B0"
}
variable "high_availability" {
  type    = string
  default = "Enabled"
}
variable "public_network_access" {
  type    = string
  default = "Disabled"
}

resource "azapi_resource" "redis" {
  type      = "Microsoft.Cache/redisEnterprise@2025-07-01"
  name      = "${var.name_prefix}-redis"
  location  = var.location
  parent_id = var.resource_group_id
  tags      = var.tags

  body = {
    sku = {
      name = var.sku_name
    }
    properties = {
      minimumTlsVersion   = "1.2"
      highAvailability    = var.high_availability
      publicNetworkAccess = var.public_network_access
    }
  }

  response_export_values = ["properties.hostName", "properties.highAvailability", "properties.redundancyMode", "properties.publicNetworkAccess"]
}

resource "azapi_resource" "redis_db" {
  type      = "Microsoft.Cache/redisEnterprise/databases@2025-07-01"
  name      = "default"
  parent_id = azapi_resource.redis.id

  body = {
    properties = {
      clientProtocol           = "Encrypted"
      port                     = 10000
      clusteringPolicy         = "EnterpriseCluster"
      evictionPolicy           = "NoEviction"
      accessKeysAuthentication = "Enabled"
      modules = [
        { name = "RediSearch" }
      ]
    }
  }
}

output "redis_id" { value = azapi_resource.redis.id }
output "redis_name" { value = azapi_resource.redis.name }
output "redis_database_id" { value = azapi_resource.redis_db.id }
output "redis_host_name" { value = azapi_resource.redis.output.properties.hostName }
output "redis_database_name" { value = azapi_resource.redis_db.name }
output "redis_high_availability" { value = azapi_resource.redis.output.properties.highAvailability }
output "redis_redundancy_mode" { value = try(azapi_resource.redis.output.properties.redundancyMode, "Unknown") }
output "redis_public_network_access" { value = azapi_resource.redis.output.properties.publicNetworkAccess }
output "redis_port" { value = 10000 }
