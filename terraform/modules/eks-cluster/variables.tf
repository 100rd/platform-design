variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "dns-failover-cluster"
}

variable "cluster_version" {
  description = "Kubernetes version to use for the EKS cluster"
  type        = string
  default     = "1.29"
}

variable "vpc_id" {
  description = "ID of the VPC where the cluster will be deployed"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs for the cluster"
  type        = list(string)
}

variable "instance_types" {
  description = "List of instance types for the node groups"
  type        = list(string)
  default     = ["m5.large"]
}

variable "min_size" {
  description = "Minimum number of nodes in the node group"
  type        = number
  default     = 3
}

variable "max_size" {
  description = "Maximum number of nodes in the node group"
  type        = number
  default     = 5
}

variable "desired_size" {
  description = "Desired number of nodes in the node group"
  type        = number
  default     = 3
}

variable "cluster_endpoint_public_access" {
  description = "Whether the EKS API server endpoint is publicly accessible. Should be false for production."
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

variable "tags" {
  description = "A map of tags to add to all resources"
  type        = map(string)
  default     = {}
}
