output "enabled" {
  description = "Whether the EFA fabric was deployed by this module."
  value       = var.enabled
}

output "mode" {
  description = "EFA exposure mode in effect (device-plugin | dra)."
  value       = var.mode
}

output "efa_resource_name" {
  description = "The resource pods reference for EFA: the device-plugin extended resource or the DRA DeviceClass."
  value       = var.mode == "device-plugin" ? "vpc.amazonaws.com/efa" : var.device_class_name
}

output "device_class_name" {
  description = "EFA netdev DRA DeviceClass name (dra mode only; null otherwise)."
  value       = var.mode == "dra" ? var.device_class_name : null
}

output "fabric_enabled" {
  description = "Whether a fabric path (device-plugin or DRA) is actually deployed."
  value       = local.use_device_plugin || local.use_dra
}

output "platform_labels" {
  description = "Effective ADR-0028 Kubernetes-plane labels."
  value       = local.platform_labels
}
