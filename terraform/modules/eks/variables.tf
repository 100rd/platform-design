variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version for the cluster"
  type        = string
  default     = "1.32"
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs"
  type        = list(string)
}

variable "karpenter_controller_instance_types" {
  description = "Instance types for Karpenter controller node group"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "karpenter_controller_desired_size" {
  description = "Desired capacity for Karpenter controller node group"
  type        = number
  default     = 2
}

variable "karpenter_controller_min_size" {
  description = "Minimum nodes for Karpenter controller node group"
  type        = number
  default     = 1
}

variable "karpenter_controller_max_size" {
  description = "Maximum nodes for Karpenter controller node group"
  type        = number
  default     = 3
}

variable "karpenter_node_iam_role_additional_policies" {
  description = "Additional IAM policies to attach to Karpenter node IAM role"
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "Tags to apply"
  type        = map(string)
  default     = {}
}
