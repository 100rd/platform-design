output "enabled" {
  description = "Whether the DCGM exporter was deployed by this module."
  value       = var.enabled
}

output "namespace" {
  description = "Namespace the DCGM exporter is installed into (null when disabled)."
  value       = var.enabled ? kubernetes_namespace.dcgm[0].metadata[0].name : null
}

output "release_name" {
  description = "Helm release name of the DCGM exporter (null when disabled)."
  value       = var.enabled ? helm_release.dcgm_exporter[0].name : null
}

output "metrics_port" {
  description = "Port on which DCGM metrics are exposed for scrape."
  value       = var.exporter_port
}

output "service_monitor_enabled" {
  description = "Whether a Prometheus-Operator ServiceMonitor was requested for scrape."
  value       = var.create_service_monitor
}

output "platform_labels" {
  description = "Effective ADR-0028 Kubernetes-plane labels applied to DCGM resources."
  value       = local.platform_labels
}
