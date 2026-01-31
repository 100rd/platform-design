output "tgw_share_arn" {
  description = "ARN of the TGW RAM resource share"
  value       = aws_ram_resource_share.tgw.arn
}

output "tgw_share_id" {
  description = "ID of the TGW RAM resource share"
  value       = aws_ram_resource_share.tgw.id
}

output "subnet_share_arn" {
  description = "ARN of the subnet RAM resource share"
  value       = length(var.shared_subnet_arns) > 0 ? aws_ram_resource_share.subnets[0].arn : ""
}
