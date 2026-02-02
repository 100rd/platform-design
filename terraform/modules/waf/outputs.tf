output "web_acl_arn" {
  description = "WAF WebACL ARN for ALB ingress annotation"
  value       = aws_wafv2_web_acl.this.arn
}

output "web_acl_id" {
  description = "WAF WebACL ID"
  value       = aws_wafv2_web_acl.this.id
}
