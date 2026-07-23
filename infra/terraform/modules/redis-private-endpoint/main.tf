# Redis private endpoint + DNS zone group. Parity with
# infrastructure/modules/redis-private-endpoint.bicep.

variable "location" { type = string }
variable "resource_group_name" { type = string }
variable "name_prefix" { type = string }
variable "tags" { type = map(string) }
variable "redis_id" { type = string }
variable "private_link_subnet_id" { type = string }
variable "redis_dns_zone_id" { type = string }

resource "azurerm_private_endpoint" "redis" {
  name                = "${var.name_prefix}-redis-pe"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_link_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "${var.name_prefix}-redis-plsc"
    private_connection_resource_id = var.redis_id
    subresource_names              = ["redisEnterprise"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "redis-dns-zone-group"
    private_dns_zone_ids = [var.redis_dns_zone_id]
  }
}

output "private_endpoint_id" { value = azurerm_private_endpoint.redis.id }
output "private_endpoint_name" { value = azurerm_private_endpoint.redis.name }
