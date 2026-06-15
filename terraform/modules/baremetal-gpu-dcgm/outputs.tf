output "enabled" {
  description = "Whether DCGM was deployed."
  value       = var.enabled
}

output "namespace" {
  description = "Namespace the DCGM exporter runs in (null when disabled)."
  value       = var.enabled ? kubernetes_namespace.dcgm[0].metadata[0].name : null
}

output "exporter_port" {
  description = "Port DCGM metrics are exposed on for scrape."
  value       = var.exporter_port
}

output "auto_taint_enabled" {
  description = "Whether the GPU-health auto-taint CronJob is deployed (XID-burst node taint)."
  value       = var.enabled && var.enable_auto_taint
}

output "platform_labels" {
  description = "Effective ADR-0028 dotted labels."
  value       = local.platform_labels
}
