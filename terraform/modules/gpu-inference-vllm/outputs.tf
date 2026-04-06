output "vllm_namespace" {
  description = "Kubernetes namespace where vLLM is deployed"
  value       = var.namespace
}

output "vllm_service_endpoint" {
  description = "In-cluster service endpoint for the vLLM OpenAI-compatible API"
  value       = "http://vllm.${var.namespace}.svc.cluster.local:8000"
}

output "vllm_service_name" {
  description = "Kubernetes Service name for vLLM"
  value       = "vllm"
}

output "resource_claim_template_name" {
  description = "Name of the DRA ResourceClaimTemplate used for GPU allocation"
  value       = var.resource_claim_template_name
}
