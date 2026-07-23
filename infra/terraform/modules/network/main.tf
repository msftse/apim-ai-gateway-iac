# Networking module — VNet with apim + privatelink subnets, NSG with the
# minimum rules for classic External-mode APIM injection, and the Redis private
# DNS zone + VNet link. Parity with infrastructure/modules/network.bicep.

variable "location" { type = string }
variable "resource_group_name" { type = string }
variable "name_prefix" { type = string }
variable "tags" { type = map(string) }
variable "vnet_address_prefix" {
  type    = string
  default = "10.20.0.0/16"
}
variable "apim_subnet_prefix" {
  type    = string
  default = "10.20.0.0/24"
}
variable "private_link_subnet_prefix" {
  type    = string
  default = "10.20.1.0/24"
}
variable "deploy_private_dns" {
  type    = bool
  default = true
}

locals {
  redis_private_dns_zone_name = "privatelink.redis.azure.net"
}

resource "azurerm_network_security_group" "apim" {
  name                = "${var.name_prefix}-apim-nsg"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  security_rule {
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
  security_rule {
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
  security_rule {
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
  security_rule {
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
  security_rule {
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
  security_rule {
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
  security_rule {
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
  security_rule {
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
  security_rule {
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

resource "azurerm_virtual_network" "this" {
  name                = "${var.name_prefix}-vnet"
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = [var.vnet_address_prefix]
  tags                = var.tags
}

resource "azurerm_subnet" "apim" {
  name                 = "apim"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.apim_subnet_prefix]
  # Classic APIM injection subnet must NOT be delegated.
}

resource "azurerm_subnet_network_security_group_association" "apim" {
  subnet_id                 = azurerm_subnet.apim.id
  network_security_group_id = azurerm_network_security_group.apim.id
}

resource "azurerm_subnet" "privatelink" {
  name                              = "privatelink"
  resource_group_name               = var.resource_group_name
  virtual_network_name              = azurerm_virtual_network.this.name
  address_prefixes                  = [var.private_link_subnet_prefix]
  private_endpoint_network_policies = "Disabled"
}

resource "azurerm_private_dns_zone" "redis" {
  count               = var.deploy_private_dns ? 1 : 0
  name                = local.redis_private_dns_zone_name
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "redis" {
  count                 = var.deploy_private_dns ? 1 : 0
  name                  = "${var.name_prefix}-redis-dns-link"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.redis[0].name
  virtual_network_id    = azurerm_virtual_network.this.id
  registration_enabled  = false
  tags                  = var.tags
}

output "vnet_id" { value = azurerm_virtual_network.this.id }
output "vnet_name" { value = azurerm_virtual_network.this.name }
output "apim_subnet_id" { value = azurerm_subnet.apim.id }
output "private_link_subnet_id" { value = azurerm_subnet.privatelink.id }
output "redis_dns_zone_id" { value = try(azurerm_private_dns_zone.redis[0].id, null) }
output "redis_dns_zone_name" { value = local.redis_private_dns_zone_name }
