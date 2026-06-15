output "enabled" {
  description = "Whether the scheduling stack was deployed."
  value       = var.enabled
}

output "namespace" {
  description = "Namespace Volcano + queues/DRA run in (null when disabled)."
  value       = var.enabled ? kubernetes_namespace.scheduling[0].metadata[0].name : null
}

output "queue_names" {
  description = "The Volcano queue names created (the UK taxonomy from 06-uk-datacenters.md)."
  value       = keys(local.queues)
}

output "device_class_names" {
  description = "The DRA DeviceClass names created (H100/H200/L40S + fractional)."
  value       = keys(local.device_classes)
}

output "platform_labels" {
  description = "Effective ADR-0028 dotted labels."
  value       = local.platform_labels
}
