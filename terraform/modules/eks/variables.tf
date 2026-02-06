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

variable "kms_key_arn" {
  description = "ARN of KMS CMK for EKS secrets envelope encryption. PCI-DSS Req 3.4. Empty string disables encryption."
  type        = string
  default     = ""
}

variable "cluster_enabled_log_types" {
  description = "List of EKS control plane log types to enable. PCI-DSS Req 10.2 requires comprehensive logging."
  type        = list(string)
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
}

# ---------------------------------------------------------------------------
# EKS Access Entries — PCI-DSS Req 7.1, 7.2, 8.5
# Maps IAM principals to Kubernetes groups for RBAC-based access control.
# Each entry maps an IAM role (typically SSO permission set) to K8s groups.
# ---------------------------------------------------------------------------
variable "access_entries" {
  description = "Map of EKS access entries. Each entry maps an IAM principal to Kubernetes groups. PCI-DSS Req 7.1 (least privilege), 7.2 (access control system), 8.5 (no shared accounts)."
  type = map(object({
    principal_arn     = string
    kubernetes_groups = list(string)
    type              = optional(string, "STANDARD")
  }))
  default = {}
}

variable "tags" {
  description = "Tags to apply"
  type        = map(string)
  default     = {}
}
