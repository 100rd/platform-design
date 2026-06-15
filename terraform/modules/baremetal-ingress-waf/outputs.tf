output "enabled" {
  description = "Whether the ingress WAF/rate-limit was deployed."
  value       = var.enabled
}

output "gateway_backend" {
  description = "Active serving gateway backend (cilium / envoy)."
  value       = var.gateway_backend
}

output "gateway_name" {
  description = "Name of the serving Gateway."
  value       = var.gateway_name
}

output "rate_limit_enabled" {
  description = "Whether a rate-limit policy (Cloud-Armor mirror) was created."
  value       = var.enabled
}

output "platform_labels" {
  description = "Effective ADR-0028 dotted labels."
  value       = local.platform_labels
}
