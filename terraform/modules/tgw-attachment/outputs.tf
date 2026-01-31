output "attachment_id" {
  description = "Transit Gateway VPC Attachment ID"
  value       = var.enabled ? aws_ec2_transit_gateway_vpc_attachment.this[0].id : ""
}

output "enabled" {
  description = "Whether the TGW attachment is enabled"
  value       = var.enabled
}
