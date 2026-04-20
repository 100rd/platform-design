output "prometheus_rule_name" {
  description = "Name of the PrometheusRule created for advanced eBPF feature alerts"
  value       = kubernetes_manifest.cilium_advanced_alerts.manifest.metadata.name
}

output "hubble_service_monitor_name" {
  description = "Name of the Hubble ServiceMonitor for Prometheus scrape"
  value       = kubernetes_manifest.hubble_service_monitor.manifest.metadata.name
}
