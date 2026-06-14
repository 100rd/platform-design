output "device_class_name" {
  description = "The name of the RoCE netdev DeviceClass (null when disabled)."
  value       = var.enabled ? var.device_class_name : null
}

output "claim_template_name" {
  description = "The name of the RDMA ResourceClaimTemplate (null when disabled)."
  value       = var.enabled ? var.claim_template_name : null
}

output "dranet_enabled" {
  description = "Whether the DRANET DRA objects were deployed."
  value       = var.enabled
}
