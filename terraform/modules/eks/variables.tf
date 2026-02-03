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
  default     = ["m5.large"]
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

variable "cluster_endpoint_public_access" {
  description = "Whether the EKS API server endpoint is publicly accessible. Should be false for production."
  type        = bool
  default     = false
}

variable "enable_vpc_cni" {
  description = "Enable AWS VPC CNI addon. Set to false to use Cilium CNI instead (recommended)."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags to apply"
  type        = map(string)
  default     = {}
}
