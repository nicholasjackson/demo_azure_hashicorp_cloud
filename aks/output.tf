output "frontend_kube_config" {
  value = azurerm_kubernetes_cluster.frontend.kube_config_raw
}

output "lb_ip" {
  value = kubernetes_service.api.load_balancer_ingress[0].ip
}