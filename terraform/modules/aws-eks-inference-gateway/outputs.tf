output "enabled" {
  description = "Whether the inference gateway objects were deployed."
  value       = var.enabled
}

output "gateway_name" {
  description = "Name of the Gateway (null when disabled)."
  value       = var.enabled ? var.gateway_name : null
}

output "inference_pool_name" {
  description = "Name of the InferencePool (null when disabled)."
  value       = var.enabled ? var.inference_pool_name : null
}

output "epp_service_name" {
  description = "Name of the Endpoint-Picker (EPP) Service (null when not deployed)."
  value       = local.deploy_epp ? "${var.inference_pool_name}-epp" : null
}

output "data_plane" {
  description = "Gateway API data plane in effect (envoy | alb)."
  value       = var.data_plane
}

output "waf_attached" {
  description = "Whether an AWS WAF WebACL ARN is wired to the serving front (ADR-0047 D4)."
  value       = var.waf_web_acl_arn != ""
}

output "inference_crd_version" {
  description = "Pinned Gateway API Inference Extension CRD version (v1 GA)."
  value       = var.inference_crd_version
}

output "platform_labels" {
  description = "Effective ADR-0028 Kubernetes-plane labels."
  value       = local.platform_labels
}
