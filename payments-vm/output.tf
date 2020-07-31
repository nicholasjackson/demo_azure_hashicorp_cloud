output "payments_ip" {
  depends_on = [azurerm_virtual_machine.vm]
  value = azurerm_public_ip.payments.ip_address
}

output "payments_user" {
  value = "azure-user"
}