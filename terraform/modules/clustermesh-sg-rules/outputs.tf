output "security_group_rule_ids" {
  description = "Map of rule name to security group rule ID"
  value       = { for k, v in aws_vpc_security_group_ingress_rule.clustermesh : k => v.id }
}

output "enabled" {
  description = "Whether ClusterMesh SG rules are enabled"
  value       = var.enabled
}
