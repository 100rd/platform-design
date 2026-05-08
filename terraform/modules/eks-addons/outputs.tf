output "addon_arns" {
  description = "Map of addon name to ARN for all deployed EKS addons."
  value       = { for k, v in aws_eks_addon.this : k => v.arn }
}

output "addon_versions" {
  description = "Map of addon name to resolved version string."
  value       = { for k, v in aws_eks_addon.this : k => v.addon_version }
}
