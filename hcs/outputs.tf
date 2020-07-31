// Login to Azure using a service id to retrieve the HCS config and ACL token
resource "null_resource" "login" {
  depends_on = [azurerm_managed_application.hcs]
  provisioner "local-exec" {
    command = <<EOF
    az login --service-principal -u ${var.client_id} -p ${var.client_secret} --tenant ${var.tenant_id} 
  EOF
  }
}

# Fetch the data from HCS
resource "null_resource" "config" {
  depends_on = [azurerm_managed_application.hcs, null_resource.config]
  provisioner "local-exec" {
    command = <<EOF
  az resource show \
  --ids "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_resource_group.example.name}/providers/Microsoft.Solutions/applications/hcs/customconsulClusters/hashicorp-consul-cluster" \
  --api-version 2018-09-01-preview \
  > ${path.module}/config.json
  EOF
  }
}

resource "null_resource" "token" {
  depends_on = [azurerm_managed_application.hcs, null_resource.config]
  provisioner "local-exec" {
    command = <<EOF
  az hcs create-token \
  --resource-group ${azurerm_resource_group.example.name} \
  --name hcs \
  > ${path.module}/token.json
  EOF
  }
}

data "local_file" "config" {
    depends_on = [null_resource.config]

    filename = "${path.module}/config.json"
}

data "local_file" "token" {
    depends_on = [null_resource.token]

    filename = "${path.module}/token.json"
}

locals {
  private_url = jsondecode(data.local_file.config.content).properties.consulPrivateEndpointUrl
  public_url = jsondecode(data.local_file.config.content).properties.consulExternalEndpointUrl
  ca_file = jsondecode(data.local_file.config.content).properties.consulCaFile
  consul_config = jsondecode(base64decode(jsondecode(data.local_file.config.content).properties.consulConfigFile))
  acl_token = jsondecode(data.local_file.token.content).masterToken.secretId
}

output "resource_group" {
  value = {
    name     = azurerm_resource_group.example.name
    location = azurerm_resource_group.example.location
  }
}

output "subnet_id" {
  value =  module.frontend-network.vnet_subnets[0]
}

output "hcs_config" {
  value = {
    private_url = local.private_url
    public_url = local.public_url 
    ca_file = local.ca_file 
    consul_config = local.consul_config
    acl_token = local.acl_token 
  }
}
