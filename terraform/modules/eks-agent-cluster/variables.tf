# variables.tf for the EKS Agent Cluster module
# Based on the existing eks-cluster module, but adapted for a Karpenter-based setup.

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
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
  description = "List of subnet IDs where the cluster control plane will be deployed"
  type        = list(string)
}

variable "cluster_endpoint_public_access" {
  description = "Whether the EKS API server endpoint is publicly accessible. Should be false for production."
  type        = bool
  default     = false
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "List of CIDR blocks which can access the Amazon EKS public API server endpoint"
  type        = list(string)
  default     = ["0.0.0.0/0"]
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

variable "access_entries" {
  description = "Map of EKS access entries. Each entry maps an IAM principal to Kubernetes groups. PCI-DSS Req 7.1, 7.2, 8.5."
  type = map(object({
    principal_arn     = string
    kubernetes_groups = list(string)
    type              = optional(string, "STANDARD")
  }))
  default = {}
}

variable "tags" {
  description = "A map of tags to add to all resources"
  type        = map(string)
  default     = {}
}
