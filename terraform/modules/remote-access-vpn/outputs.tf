# ---------------------------------------------------------------------------------------------------------------------
# Remote-Access VPN — outputs (ADR-0013)
# ---------------------------------------------------------------------------------------------------------------------

output "instance_id" {
  description = "EC2 instance ID of the VPN host."
  value       = aws_instance.vpn.id
}

output "instance_private_ip" {
  description = "Primary private IP of the VPN host. Used as the NLB IP-mode target (target_type=ip)."
  value       = aws_instance.vpn.private_ip
}

output "nlb_dns_name" {
  description = "DNS name of the NLB. Prefer nlb_eip_public_ip as the stable endpoint."
  value       = aws_lb.vpn.dns_name
}

output "nlb_arn" {
  description = "ARN of the VPN Network Load Balancer."
  value       = aws_lb.vpn.arn
}

output "nlb_eip_public_ip" {
  description = "Stable public EIP attached to the NLB. This is the VPN client endpoint — survives instance replacement."
  value       = aws_eip.nlb.public_ip
}

output "nlb_eip_allocation_id" {
  description = "EIP allocation ID for the NLB EIP."
  value       = aws_eip.nlb.allocation_id
}

output "instance_security_group_id" {
  description = "ID of the instance-level security group."
  value       = aws_security_group.instance.id
}

output "nlb_security_group_id" {
  description = "ID of the NLB edge security group."
  value       = aws_security_group.nlb.id
}

output "iam_role_arn" {
  description = "ARN of the VPN instance IAM role."
  value       = aws_iam_role.vpn.arn
}

output "vpn_client_cidr" {
  description = "Full VPN client pool CIDR. Add return routes for this CIDR on permitted spoke RTs (see inter-vpc-security module)."
  value       = var.vpn_client_cidr
}

output "vpn_ops_subpool_cidr" {
  description = "Ops-tier VPN sub-pool CIDR. Only this sub-pool is routed to production (ADR-0013)."
  value       = var.vpn_ops_subpool_cidr
}

output "vpn_standard_subpool_cidr" {
  description = "Standard-tier VPN sub-pool CIDR. Blocked from production by the prod NACL backstop (ADR-0013)."
  value       = var.vpn_standard_subpool_cidr
}

output "flow_log_group_name" {
  description = "CloudWatch log group name for VPC flow logs."
  value       = aws_cloudwatch_log_group.flow_logs.name
}

output "app_log_group_name" {
  description = "CloudWatch log group name for VPN application logs."
  value       = aws_cloudwatch_log_group.app_logs.name
}

output "datastore_secret_arn" {
  description = "ARN of the Secrets Manager secret shell for the datastore URI (value set out-of-band)."
  value       = aws_secretsmanager_secret.datastore_uri.arn
}

output "setup_key_secret_arn" {
  description = "ARN of the Secrets Manager secret shell for the VPN setup key (value set out-of-band)."
  value       = aws_secretsmanager_secret.setup_key.arn
}

output "datastore_ebs_volume_id" {
  description = "EBS volume ID for the dedicated VPN datastore volume."
  value       = aws_ebs_volume.datastore.id
}
