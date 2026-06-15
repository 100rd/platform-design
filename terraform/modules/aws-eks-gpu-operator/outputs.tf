output "enabled" {
  description = "Whether the GPU operator was deployed by this module."
  value       = var.enabled
}

output "gpu_operator_namespace" {
  description = "Namespace the GPU operator is installed into (null when disabled)."
  value       = var.enabled ? kubernetes_namespace.gpu_operator[0].metadata[0].name : null
}

output "gpu_operator_version" {
  description = "Pinned chart version deployed."
  value       = var.chart_version
}

output "dra_enabled" {
  description = "Whether the NVIDIA DRA driver is enabled (ADR-0044 D2)."
  value       = var.dra_driver_enabled
}

output "driver_enabled" {
  description = "Effective driver-install toggle (false on Bottlerocket pre-baked AMI, true on AL2023; ADR-0044 D1)."
  value       = local.driver_enabled
}

output "platform_labels" {
  description = "Effective ADR-0028 Kubernetes-plane labels."
  value       = local.platform_labels
}
