# ---------------------------------------------------------------------------------------------------------------------
# GPU Inference Scheduling Policies — Outputs
# ---------------------------------------------------------------------------------------------------------------------

output "priorityclass_system_critical" {
  description = "Name of the gpu-system-critical PriorityClass"
  value       = kubernetes_priority_class_v1.gpu_system_critical.metadata[0].name
}

output "priorityclass_training_high" {
  description = "Name of the gpu-training-high PriorityClass"
  value       = kubernetes_priority_class_v1.gpu_training_high.metadata[0].name
}

output "priorityclass_inference_medium" {
  description = "Name of the gpu-inference-medium PriorityClass"
  value       = kubernetes_priority_class_v1.gpu_inference_medium.metadata[0].name
}

output "priorityclass_batch_low" {
  description = "Name of the gpu-batch-low PriorityClass"
  value       = kubernetes_priority_class_v1.gpu_batch_low.metadata[0].name
}

output "priorityclass_names" {
  description = "Map of all PriorityClass names keyed by tier"
  value = {
    system_critical  = kubernetes_priority_class_v1.gpu_system_critical.metadata[0].name
    training_high    = kubernetes_priority_class_v1.gpu_training_high.metadata[0].name
    inference_medium = kubernetes_priority_class_v1.gpu_inference_medium.metadata[0].name
    batch_low        = kubernetes_priority_class_v1.gpu_batch_low.metadata[0].name
  }
}

output "example_podgroup_name" {
  description = "Name of the example gang-scheduled PodGroup"
  value       = "distributed-training-example"
}

output "resource_quota_namespaces" {
  description = "List of namespaces with GPU ResourceQuotas applied"
  value       = var.enable_resource_quotas ? keys(var.gpu_quota_namespaces) : []
}
