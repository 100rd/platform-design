output "gpu_operator_namespace" {
  description = "Namespace where GPU Operator is installed"
  value       = helm_release.gpu_operator.namespace
}

output "gpu_operator_version" {
  description = "Installed GPU Operator version"
  value       = helm_release.gpu_operator.version
}

output "dra_enabled" {
  description = "Whether DRA driver is enabled"
  value       = true
}
