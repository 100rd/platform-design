# ---------------------------------------------------------------------------------------------------------------------
# aws-eks-gpu — greenfield EKS GPU ML cluster (ADR-0044 D1/D2/D6)
# ---------------------------------------------------------------------------------------------------------------------

variable "enabled" {
  description = "Master toggle. When false the module creates no EKS cluster (default-OFF; apply-gated)."
  type        = bool
  default     = false
  nullable    = false
}

variable "cluster_name" {
  description = "Name of the greenfield EKS GPU ML cluster."
  type        = string
  default     = "aws-eks-gpu"
}

variable "cluster_version" {
  description = "Kubernetes version. Must be >= 1.33 for DRA GA on EKS (ADR-0044 D2); 1.34+ recommended where DRA is upstream-GA default."
  type        = string
  default     = "1.34"

  validation {
    condition     = tonumber(split(".", var.cluster_version)[1]) >= 33
    error_message = "cluster_version must be >= 1.33 — DRA is GA on EKS from 1.33 (ADR-0044 D2)."
  }
}

variable "vpc_id" {
  description = "VPC ID (from aws-eks-gpu-vpc)."
  type        = string
  default     = ""
}

variable "subnet_ids" {
  description = "Subnet IDs for the EKS control plane / general workloads (from aws-eks-gpu-vpc private subnets)."
  type        = list(string)
  default     = []
}

variable "cluster_endpoint_public_access" {
  description = "Whether the EKS API endpoint is publicly accessible. Keep false for the GPU ML cluster (private)."
  type        = bool
  default     = false
  nullable    = false
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "CIDR blocks allowed to reach the public API endpoint (only relevant when public access is enabled)."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "kms_key_arn" {
  description = "KMS CMK ARN for EKS secrets envelope encryption (PCI-DSS Req 3.4). Empty string disables encryption."
  type        = string
  default     = ""
}

variable "cluster_enabled_log_types" {
  description = "EKS control-plane log types to enable (audit trail, PCI-DSS Req 10.2)."
  type        = list(string)
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
}

variable "enable_dra_feature_gate" {
  description = "Whether the cluster is intended to run with the DynamicResourceAllocation feature gate (GA on EKS 1.33+). Surfaced as a cluster tag for conformance checks (ADR-0044 D2); the gate itself is managed by the EKS version."
  type        = bool
  default     = true
  nullable    = false
}

variable "tags" {
  description = "ADR-0028 platform taxonomy tags (platform:system / platform:component / platform:owner / platform:env / platform:managed-by) applied to every resource."
  type        = map(string)
  default     = {}
  nullable    = false
}
