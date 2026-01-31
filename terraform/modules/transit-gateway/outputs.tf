output "transit_gateway_id" {
  description = "The ID of the Transit Gateway"
  value       = aws_ec2_transit_gateway.this.id
}

output "transit_gateway_arn" {
  description = "The ARN of the Transit Gateway"
  value       = aws_ec2_transit_gateway.this.arn
}

output "route_table_ids" {
  description = "Map of route table name to route table ID"
  value       = { for k, v in aws_ec2_transit_gateway_route_table.this : k => v.id }
}

output "transit_gateway_owner_id" {
  description = "The AWS account ID of the TGW owner"
  value       = aws_ec2_transit_gateway.this.owner_id
}
