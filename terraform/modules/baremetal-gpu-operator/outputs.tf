output "enabled" {
  description = "Whether the GPU operator was deployed."
  value       = var.enabled
}

output "namespace" {
  description = "Namespace the GPU operator is installed into (null when disabled)."
  value       = var.enabled ? kubernetes_namespace.gpu_operator[0].metadata[0].name : null
}

output "release_name" {
  description = "Helm release name of the GPU operator (null when disabled)."
  value       = var.enabled ? helm_release.gpu_operator[0].name : null
}

output "chart_version" {
  description = "Pinned chart version that was deployed."
  value       = var.chart_version
}

output "driver_less" {
  description = "Confirms the Operator runs driver-less (true): the driver ships in the Talos system extension (ADR-0050), not the Operator."
  value       = var.driver_enabled == false && var.toolkit_enabled == false
}

output "platform_labels" {
  description = "Effective ADR-0028 dotted labels."
  value       = local.platform_labels
}
