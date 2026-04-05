output "endpoints" {
  description = "Map of endpoint service name to endpoint object (id, dns_entry, state)"
  value       = module.vpc_endpoints.endpoints
}

output "endpoint_ids" {
  description = "Map of endpoint service name to endpoint ID"
  value       = { for k, v in module.vpc_endpoints.endpoints : k => v.id }
}
