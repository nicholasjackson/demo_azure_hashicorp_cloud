resource "azurerm_marketplace_agreement" "hcs" {
  count     = var.accept_marketplace_agreement ? 1 : 0
  publisher = "hashicorp-4665790"
  offer     = "hcs-production"
  plan      = "on-demand"
}

resource "random_string" "storageaccountname" {
  length  = 13
  upper   = false
  lower   = true
  special = false
}

resource "random_string" "blobcontainername" {
  length  = 13
  upper   = false
  lower   = true
  special = false
}

resource "azurerm_managed_application" "hcs" {
  depends_on = [azurerm_marketplace_agreement.hcs]

  name                        = "hcs"
  location                    = azurerm_resource_group.example.location 
  resource_group_name         = azurerm_resource_group.example.name 
  kind                        = "MarketPlace"
  managed_resource_group_name = var.managed_resource_group

  plan {
    name      = "on-demand"
    product   = "hcs-production"
    publisher = "hashicorp-4665790"
    version   = "0.0.39"
  }

  parameters = {
    initialConsulVersion  = var.consul_version
    storageAccountName    = random_string.storageaccountname.result
    blobContainerName     = random_string.blobcontainername.result
    clusterMode           = "DEVELOPMENT"
    clusterName           = "hashicorp-consul-cluster"
    consulDataCenter      = azurerm_resource_group.example.location
    numServers            = "1"
    numServersDevelopment = "1"
    automaticUpgrades     = "disabled"
    consulConnect         = "enabled"
    externalEndpoint      = "enabled"
    snapshotInterval      = "1d"
    snapshotRetention     = "1m"
    consulVnetCidr        = "10.0.0.0/24"
    location              = azurerm_resource_group.example.location 
    providerBaseURL       = "https://ama-api.hashicorp.cloud/consulama/2020-07-09"
    email                 = var.email
  }
}

data "azurerm_virtual_network" "hcs" {
  depends_on          = [azurerm_managed_application.hcs]
  name                = "hvn-consul-ama-hashicorp-consul-cluster-vnet"
  resource_group_name = var.managed_resource_group
}

resource "azurerm_virtual_network_peering" "hcs-frontend" {
  lifecycle {
    ignore_changes = [remote_virtual_network_id]
  }

  name                      = "HCSToFrontend"
  resource_group_name       = var.managed_resource_group
  virtual_network_name      = data.azurerm_virtual_network.hcs.name
  remote_virtual_network_id = module.frontend-network.vnet_id
}

resource "azurerm_virtual_network_peering" "frontend-hcs" {
  lifecycle {
    ignore_changes = [remote_virtual_network_id]
  }

  name                      = "FrontendToHCS"
  resource_group_name       = azurerm_resource_group.example.name 
  virtual_network_name      = module.frontend-network.vnet_name
  remote_virtual_network_id = data.azurerm_virtual_network.hcs.id
}