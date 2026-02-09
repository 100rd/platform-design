output "accelerator_id" {
  description = "ID of the Global Accelerator"
  value       = var.enabled ? aws_globalaccelerator_accelerator.this[0].id : ""
}

output "accelerator_dns_name" {
  description = "DNS name of the Global Accelerator"
  value       = var.enabled ? aws_globalaccelerator_accelerator.this[0].dns_name : ""
}

output "accelerator_ip_sets" {
  description = "IP address sets assigned to the Global Accelerator"
  value       = var.enabled ? aws_globalaccelerator_accelerator.this[0].ip_sets : []
}

output "listener_arns" {
  description = "List of ARNs for the Global Accelerator listeners"
  value       = [for l in aws_globalaccelerator_listener.this : l.id]
}

output "endpoint_group_arns" {
  description = "Map of region to endpoint group ARN"
  value       = { for k, v in aws_globalaccelerator_endpoint_group.this : k => v.id }
}
