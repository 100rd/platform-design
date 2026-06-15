output "enabled" {
  description = "Whether DCGM was deployed by this module."
  value       = var.enabled
}

output "dcgm_namespace" {
  description = "Namespace the DCGM exporter is installed into (null when disabled)."
  value       = var.enabled ? kubernetes_namespace.dcgm[0].metadata[0].name : null
}

output "exporter_version" {
  description = "Pinned dcgm-exporter chart version deployed."
  value       = var.chart_version
}

output "service_monitor_enabled" {
  description = "Whether a ServiceMonitor is rendered for the metrics backend."
  value       = var.enabled && var.create_service_monitor
}

output "auto_taint_enabled" {
  description = "Whether the GPU-health auto-taint CronJob is deployed (ADR-0044 D1)."
  value       = local.deploy_taint
}

output "metrics_backend" {
  description = "Metrics stack the exporter targets (ADR-0026)."
  value       = var.metrics_backend
}

output "platform_labels" {
  description = "Effective ADR-0028 Kubernetes-plane labels."
  value       = local.platform_labels
}
