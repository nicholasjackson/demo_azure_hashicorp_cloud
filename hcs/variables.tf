variable "managed_resource_group" {
  default = "mrg-hcs-example"
}

variable "resource_group" {
  default = "hcs-example"
}

variable "accept_marketplace_agreement" {
  default = false
}

variable "consul_version" {
  default = "v1.8.0"
}

variable "email" {
  default = "test@test.com"
}


// required for AZ command line login
variable "client_id" {}
variable "tenant_id" {}
variable "client_secret" {}