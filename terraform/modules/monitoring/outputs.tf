output "prometheus_helm_release_name" {
  value = var.enable_prometheus ? helm_release.kube_prometheus_stack[0].name : ""
}

output "grafana_enabled" {
  value = var.enable_grafana
}
