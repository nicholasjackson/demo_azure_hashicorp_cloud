provider "azurerm" {
  version = "=2.13.0"
  features {}
}

resource "azurerm_resource_group" "example" {
  name     = var.resource_group
  location = "East US"
}

data "azurerm_client_config" "current" {
}

