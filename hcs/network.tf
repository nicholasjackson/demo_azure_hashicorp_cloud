module "frontend-network" {
  source              = "Azure/network/azurerm"
  resource_group_name = azurerm_resource_group.example.name
  vnet_name           = "frontend-vnet"
  address_space       = "10.2.0.0/16"
  subnet_prefixes     = ["10.2.0.0/24"]
  subnet_names        = ["AKS"]
}