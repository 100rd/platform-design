output "release_name" {
  description = "Name of the Karpenter Helm release"
  value       = helm_release.karpenter.name
}

output "release_version" {
  description = "Version of installed Karpenter chart"
  value       = helm_release.karpenter.version
}

output "namespace" {
  description = "Namespace where Karpenter is installed"
  value       = helm_release.karpenter.namespace
}

output "status" {
  description = "Status of Karpenter Helm release"
  value       = helm_release.karpenter.status
}

output "service_account_name" {
  description = "Name of the Karpenter service account"
  value       = "karpenter"
}

output "node_iam_role_name" {
  description = "IAM role name for Karpenter-provisioned nodes (passthrough from input)"
  value       = var.karpenter_node_iam_role_name
}

output "controller_role_arn" {
  description = "IAM role ARN for Karpenter controller (passthrough from input)"
  value       = var.karpenter_controller_role_arn
}

output "interruption_queue_name" {
  description = "SQS queue name for interruption handling (passthrough from input)"
  value       = var.karpenter_interruption_queue_name
}

output "cluster_name" {
  description = "EKS cluster name (passthrough from input)"
  value       = var.cluster_name
}
