variable "managed_resource_group" {
  default = "mrg-hcs-example"
}

variable "resource_group" {
  default = "hcs-example"
}

variable "accept_marketplace_aggrement" {
  default = 1
}

variable "consul_version" {
  default = "v1.8.0"
}


// required for AZ command line login
variable "client_id" {}
variable "tenant_id" {}
variable "client_secret" {}