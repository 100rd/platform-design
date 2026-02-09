output "nlb_arn" {
  description = "ARN of the Network Load Balancer"
  value       = var.enabled ? aws_lb.this[0].arn : ""
}

output "nlb_dns_name" {
  description = "DNS name of the Network Load Balancer"
  value       = var.enabled ? aws_lb.this[0].dns_name : ""
}

output "nlb_zone_id" {
  description = "Route 53 hosted zone ID of the Network Load Balancer"
  value       = var.enabled ? aws_lb.this[0].zone_id : ""
}

output "target_group_arn" {
  description = "ARN of the NLB target group for pod registration"
  value       = var.enabled ? aws_lb_target_group.this[0].arn : ""
}
