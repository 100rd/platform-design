output "peering_attachment_id" {
  description = "Transit Gateway peering attachment ID"
  value       = var.enabled ? aws_ec2_transit_gateway_peering_attachment.this[0].id : ""
}

output "peering_attachment_state" {
  description = "State of the peering attachment (pendingAcceptance, available, etc.)"
  value       = var.enabled ? aws_ec2_transit_gateway_peering_attachment_accepter.this[0].id : ""
}

output "enabled" {
  description = "Whether TGW peering is enabled"
  value       = var.enabled
}
