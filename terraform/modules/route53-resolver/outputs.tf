output "inbound_endpoint_id" {
  description = "Inbound resolver endpoint ID"
  value       = var.enable_inbound ? aws_route53_resolver_endpoint.inbound[0].id : ""
}

output "inbound_ip_addresses" {
  description = "IP addresses of the inbound resolver endpoint"
  value       = var.enable_inbound ? aws_route53_resolver_endpoint.inbound[0].ip_address : []
}

output "outbound_endpoint_id" {
  description = "Outbound resolver endpoint ID"
  value       = var.enable_outbound ? aws_route53_resolver_endpoint.outbound[0].id : ""
}

output "forwarding_rule_ids" {
  description = "Map of forwarding rule name to rule ID"
  value       = { for k, v in aws_route53_resolver_rule.forward : k => v.id }
}

output "resolver_security_group_id" {
  description = "Security group ID for resolver endpoints"
  value       = (var.enable_inbound || var.enable_outbound) ? aws_security_group.resolver[0].id : ""
}
