data "terraform_remote_state" "hcs" {
  backend = "local"

  config = {
    path = "../hcs/terraform.tfstate"
  }
}

provider "consul" {
  address    = data.terraform_remote_state.hcs.outputs.hcs_config.public_url
  datacenter = data.terraform_remote_state.hcs.outputs.hcs_config.consul_config.datacenter
  token      = data.terraform_remote_state.hcs.outputs.hcs_config.acl_token
}

resource "consul_acl_policy" "payments" {
  name        = "payments-policy"
  rules       = <<-RULE
    node "payments" {
      policy = "write"
    }

    agent "payments" {
      policy = "write"
    }

    key_prefix "_rexec" {
      policy = "write"
    }

    service "payments" {
    	policy = "write"
    }

    service "payments-sidecar-proxy" {
    	policy = "write"
    }

    service_prefix "" {
    	policy = "read"
    }

    node_prefix "" {
    	policy = "read"
    }
  RULE
}

resource "consul_acl_role" "payments-role" {
  name = "payments-role"
  description = "Role for the payments service"

  policies = [
      "${consul_acl_policy.payments.id}"
  ]
}

resource "consul_acl_auth_method" "azure-jwt" {
  name = "my-jwt"
  type = "jwt"
  config_json = <<EOF
{
  "BoundAudiences": [
    "https://management.azure.com/"
  ],
  "BoundIssuer": "https://sts.windows.net/${var.tenant_id}/",
  "JWKSURL":"https://login.microsoftonline.com/${var.tenant_id}/discovery/v2.0/keys",
  "ClaimMappings": {
      "id": "xms_mirid"
  }
}
  EOF
}

resource "consul_acl_binding_rule" "payments-rule" {
    auth_method = consul_acl_auth_method.azure-jwt.name
    description = "Rule to allow payments vm to login with azure jwt"
    selector    = "value.xms_mirid matches `.*/payments`"
    bind_type   = "role"
    bind_name   = "payments-role"
}

resource "azurerm_public_ip" "payments" {
  name                = "payments-ip"
  resource_group_name = data.terraform_remote_state.hcs.outputs.resource_group.name
  location            = data.terraform_remote_state.hcs.outputs.resource_group.location
  allocation_method   = "Static"
}

resource "azurerm_network_interface" "vm" {
  name                = "vm-nic"
  resource_group_name = data.terraform_remote_state.hcs.outputs.resource_group.name
  location            = data.terraform_remote_state.hcs.outputs.resource_group.location

  ip_configuration {
    name                          = "configuration"
    subnet_id =  data.terraform_remote_state.hcs.outputs.subnet_id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id = azurerm_public_ip.payments.id
  }
}

resource "azurerm_user_assigned_identity" "vm" {
  resource_group_name = data.terraform_remote_state.hcs.outputs.resource_group.name
  location            = data.terraform_remote_state.hcs.outputs.resource_group.location

  name = "payments"
}

resource "azurerm_virtual_machine" "payments" {
  name                  = "payments"
  resource_group_name = data.terraform_remote_state.hcs.outputs.resource_group.name
  location            = data.terraform_remote_state.hcs.outputs.resource_group.location
  
  network_interface_ids = [azurerm_network_interface.vm.id]
  vm_size               = "Standard_D1_v2"

  delete_os_disk_on_termination    = true
  delete_data_disks_on_termination = true

  identity {
    type = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.vm.id]
  }

  storage_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "16.04-LTS"
    version   = "latest"
  }
  storage_os_disk {
    name              = "vm-disk"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }
  os_profile {
    computer_name  = "payments"
    admin_username = "azure-user"
    custom_data    = templatefile(
      "${path.module}/scripts/vm.sh",
      {
        consul_gossip_key = data.terraform_remote_state.hcs.outputs.hcs_config.consul_config.encrypt
        ca                = base64decode(data.terraform_remote_state.hcs.outputs.hcs_config.ca_file)
        consul_join_addr  = data.terraform_remote_state.hcs.outputs.hcs_config.consul_config.retry_join[0]
        consul_datacenter = data.terraform_remote_state.hcs.outputs.hcs_config.consul_config.datacenter
      }
    )
  }

  os_profile_linux_config {
    disable_password_authentication = true
    ssh_keys {
      path     = "/home/azure-user/.ssh/authorized_keys"
      key_data = var.ssh_public_key
    }
  }

  tags = {
    environment = "staging"
  }
}