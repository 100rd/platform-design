output "security_policy_id" {
  description = "The ID of the Cloud Armor security policy (attach to a backend service); null when disabled."
  value       = var.enabled ? google_compute_security_policy.this[0].id : null
}

output "security_policy_name" {
  description = "The name of the Cloud Armor security policy; null when disabled."
  value       = var.enabled ? google_compute_security_policy.this[0].name : null
}

output "security_policy_self_link" {
  description = "The self-link of the Cloud Armor security policy; null when disabled."
  value       = var.enabled ? google_compute_security_policy.this[0].self_link : null
}
