output "enabled" {
  description = "Whether Volcano + DRA classes were deployed by this module."
  value       = var.enabled
}

output "volcano_namespace" {
  description = "Namespace Volcano is installed into (null when disabled)."
  value       = var.enabled ? kubernetes_namespace.scheduling[0].metadata[0].name : null
}

output "volcano_version" {
  description = "Pinned Volcano chart version deployed."
  value       = var.chart_version
}

output "queue_names" {
  description = "Fair-share Queue names (training / inference / batch)."
  value       = ["training", "inference", "batch"]
}

output "device_class_names" {
  description = "DRA DeviceClass names created (ADR-0044 D2)."
  value       = keys(local.device_class_objs)
}

output "dra_enabled" {
  description = "Whether the Volcano dra plugin is enabled (gang-schedules GPU/EFA ResourceClaims)."
  value       = var.enable_dra
}

output "platform_labels" {
  description = "Effective ADR-0028 Kubernetes-plane labels."
  value       = local.platform_labels
}
