data "terraform_remote_state" "hcs" {
  backend = "local"

  config = {
    path = "../hcs/terraform.tfstate"
  }
}

resource "azurerm_kubernetes_cluster" "frontend" {
  name                = "frontend-aks"
  resource_group_name = data.terraform_remote_state.hcs.outputs.resource_group.name
  location            = data.terraform_remote_state.hcs.outputs.resource_group.location

  dns_prefix          = "frontend"

  default_node_pool {
    name           = "default"
    node_count     = 1
    vm_size        = "Standard_D2_v2"
    vnet_subnet_id =  data.terraform_remote_state.hcs.outputs.subnet_id
  }

  network_profile {
    network_plugin = "azure"
  }

  service_principal {
    client_id     = var.client_id
    client_secret = var.client_secret
  }
}

provider "kubernetes" {
  load_config_file = false

  host                   = azurerm_kubernetes_cluster.frontend.kube_config.0.host
  username               = azurerm_kubernetes_cluster.frontend.kube_config.0.username
  password               = azurerm_kubernetes_cluster.frontend.kube_config.0.password
  client_certificate     = base64decode(azurerm_kubernetes_cluster.frontend.kube_config.0.client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.frontend.kube_config.0.client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.frontend.kube_config.0.cluster_ca_certificate)
}



// Add the Helm chart for Consul on AKS
provider "helm" {
  kubernetes {
    load_config_file = false

    host                   = azurerm_kubernetes_cluster.frontend.kube_config.0.host
    username               = azurerm_kubernetes_cluster.frontend.kube_config.0.username
    password               = azurerm_kubernetes_cluster.frontend.kube_config.0.password
    client_certificate     = base64decode(azurerm_kubernetes_cluster.frontend.kube_config.0.client_certificate)
    client_key             = base64decode(azurerm_kubernetes_cluster.frontend.kube_config.0.client_key)
    cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.frontend.kube_config.0.cluster_ca_certificate)
  }
}

resource "kubernetes_secret" "consul-bootstrap" {
  metadata {
    name = "consul-hcs-bootstrap"
  }

  data = {
    token = data.terraform_remote_state.hcs.outputs.hcs_config.acl_token
    gossipEncryptionKey = data.terraform_remote_state.hcs.outputs.hcs_config.consul_config.encrypt
    caCert = base64decode(data.terraform_remote_state.hcs.outputs.hcs_config.ca_file)
  }
}

locals {
  helm_values = <<EOF
global:
  enabled: false
  name: consul
  datacenter: ${data.terraform_remote_state.hcs.outputs.hcs_config.consul_config.datacenter}
  acls:
    manageSystemACLs: true
    bootstrapToken:
      secretName: ${kubernetes_secret.consul-bootstrap.metadata[0].name}
      secretKey: token
  gossipEncryption:
    secretName: ${kubernetes_secret.consul-bootstrap.metadata[0].name}
    secretKey: gossipEncryptionKey
  tls:
    enabled: true
    enableAutoEncrypt: true
    caCert:
      secretName: ${kubernetes_secret.consul-bootstrap.metadata[0].name}
      secretKey: caCert
externalServers:
  enabled: true
  hosts: ['${data.terraform_remote_state.hcs.outputs.hcs_config.consul_config.retry_join[0]}']
  httpsPort: 443
  useSystemRoots: true
  k8sAuthMethodHost: ${azurerm_kubernetes_cluster.frontend.kube_config.0.host}
client:
  enabled: true
  # If you are using Kubenet in your AKS cluster (the default network),
  # uncomment the line below.
  # exposeGossipPorts: true
  join: ['${data.terraform_remote_state.hcs.outputs.hcs_config.consul_config.retry_join[0]}']
connectInject:
  enabled: true
EOF
}

resource "helm_release" "local" {
  name       = "consul"
  chart      = "./charts/consul-helm-0.23.1"

  values = [
    "${local.helm_values}"
  ]
}

resource "kubernetes_service_account" "api" {
  metadata {
    name = "api"
  }
}

// Run the application
resource "kubernetes_deployment" "api" {
  depends_on = [helm_release.local]

  metadata {
    name = "api"
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "api"
      }
    }

    template {
      metadata {
        annotations = {
          "consul.hashicorp.com/connect-inject" = "true"
          "consul.hashicorp.com/connect-service-upstreams" = "payments:9091"
        }

        labels = {
          app = "api"
        }
      }

      spec {
        service_account_name = kubernetes_service_account.api.metadata[0].name
        automount_service_account_token = true

        container {
          image = "nicholasjackson/fake-service:v0.14.1"
          name  = "api"

          env {
            name = "UPSTREAM_URIS"
            value = "http://localhost:9091"
          }
          env {
            name = "NAME"
            value = "API"
          }

          resources {
            limits {
              cpu    = "0.5"
              memory = "512Mi"
            }
            requests {
              cpu    = "250m"
              memory = "50Mi"
            }
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "api" {
  metadata {
    name = "terraform-example"
  }

  spec {
    selector = {
      app = "api"
    }

    session_affinity = "ClientIP"
    port {
      port        = 80
      target_port = 9090
    }

    type = "LoadBalancer"
  }
}

provider "consul" {
  address    = data.terraform_remote_state.hcs.outputs.hcs_config.public_url
  datacenter = data.terraform_remote_state.hcs.outputs.hcs_config.consul_config.datacenter
  token      = data.terraform_remote_state.hcs.outputs.hcs_config.acl_token
}

resource "consul_intention" "payments" {
  source_name      = "api"
  destination_name = "payments"
  action           = "allow"
}