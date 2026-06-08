# ---------------------------------------------------------------------------------------------------------------------
# VPC Lattice Resource Connectivity — Outputs (ADR-0023)
# ---------------------------------------------------------------------------------------------------------------------

output "resource_gateway_id" {
  description = "ID of the Resource Gateway. Consumers/operators reference this when wiring the resource-owning VPC ingress."
  value       = aws_vpclattice_resource_gateway.this.id
}

output "resource_gateway_arn" {
  description = "ARN of the Resource Gateway."
  value       = aws_vpclattice_resource_gateway.this.arn
}

output "resource_configuration_id" {
  description = "ID of the ARN-type Resource Configuration fronting the shared resource (e.g. the RDS DB ARN)."
  value       = aws_vpclattice_resource_configuration.this.id
}

output "resource_configuration_arn" {
  description = "ARN of the Resource Configuration."
  value       = aws_vpclattice_resource_configuration.this.arn
}

output "service_network_id" {
  description = "ID of the Service Network. Consumers create a service-network VPC association/endpoint against this to reach the resource."
  value       = aws_vpclattice_service_network.this.id
}

output "service_network_arn" {
  description = "ARN of the Service Network — the unit shared cross-account via RAM."
  value       = aws_vpclattice_service_network.this.arn
}

output "service_network_resource_association_id" {
  description = "ID of the Service Network <-> Resource Configuration association."
  value       = aws_vpclattice_service_network_resource_association.this.id
}

output "auth_policy_id" {
  description = "ID of the IAM auth policy attached to the Service Network (empty when enable_auth_policy = false)."
  value       = try(aws_vpclattice_auth_policy.this[0].id, "")
}

output "ram_share_arn" {
  description = "ARN of the RAM resource share for the Service Network (empty when enable_ram_share = false)."
  value       = try(aws_ram_resource_share.this[0].arn, "")
}
