output "role_arn" {
  description = "ARN of the EBS CSI driver Pod Identity IAM role. The association binds the controller ServiceAccount to this role; no IRSA annotation is required."
  value       = aws_iam_role.this.arn
}

output "role_name" {
  description = "Name of the EBS CSI driver Pod Identity IAM role."
  value       = aws_iam_role.this.name
}

output "policy_arn" {
  description = "ARN of the ABAC-scoped EC2 volume-operations policy attached to the EBS CSI role."
  value       = aws_iam_policy.ebs_csi.arn
}

output "association_id" {
  description = "ID of the EKS Pod Identity association (cluster + namespace + ServiceAccount -> role)."
  value       = aws_eks_pod_identity_association.this.association_id
}

output "association_arn" {
  description = "ARN of the EKS Pod Identity association."
  value       = aws_eks_pod_identity_association.this.association_arn
}
