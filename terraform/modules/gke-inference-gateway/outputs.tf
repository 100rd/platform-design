output "gateway_name" {
  description = "The name of the Inference Gateway (null when disabled)."
  value       = var.enabled ? var.gateway_name : null
}

output "inference_pool_name" {
  description = "The name of the InferencePool (null when disabled)."
  value       = var.enabled ? var.inference_pool_name : null
}

output "inference_model_names" {
  description = "Names of the InferenceObjective objects created."
  value       = var.enabled ? [for m in var.inference_models : m.name] : []
}

output "cloud_armor_attached" {
  description = "Whether a Cloud Armor GCPBackendPolicy was attached."
  value       = var.enabled && var.cloud_armor_policy_id != null
}
