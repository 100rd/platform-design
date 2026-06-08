variable "project" {
  description = "Project name used in IAM role/policy naming (e.g. 'platform-design')."
  type        = string
  default     = "platform-design"

  validation {
    condition     = length(var.project) > 0
    error_message = "project must not be empty."
  }
}

variable "cluster_name" {
  description = "Name of the EKS cluster the Pod Identity association is created on. Also used in IAM role naming and (optionally) as an ABAC eks-cluster-name condition."
  type        = string

  validation {
    condition     = length(var.cluster_name) > 0
    error_message = "cluster_name must not be empty."
  }
}

variable "namespace" {
  description = "Kubernetes namespace of the EBS CSI controller ServiceAccount. Defaults to 'kube-system'. Drives the ABAC kubernetes-namespace policy condition."
  type        = string
  default     = "kube-system"
  nullable    = false
}

variable "service_account" {
  description = "Kubernetes ServiceAccount name bound to the Pod Identity role. Defaults to 'ebs-csi-controller-sa' (the aws-ebs-csi-driver controller SA)."
  type        = string
  default     = "ebs-csi-controller-sa"
  nullable    = false
}

variable "kms_key_arns" {
  description = "List of KMS CMK ARNs for encrypted EBS volumes. Empty list (default) means all keys ('*'); pin to the volume-encryption CMK(s) in production."
  type        = list(string)
  default     = []
  nullable    = false
}

variable "iam_path" {
  description = "IAM path for the role and policy. Useful for organising workload-identity roles (e.g. '/pod-identity/')."
  type        = string
  default     = "/pod-identity/"

  validation {
    condition     = can(regex("^/.*/$", var.iam_path))
    error_message = "iam_path must begin and end with '/' (e.g. '/pod-identity/')."
  }
}

variable "max_session_duration" {
  description = "Maximum IAM role session duration in seconds. Pod Identity caches assumed credentials, so the default 3600s (1h) is sufficient for the EBS CSI controller's reconcile loop."
  type        = number
  default     = 3600

  validation {
    condition     = var.max_session_duration >= 3600 && var.max_session_duration <= 43200
    error_message = "max_session_duration must be between 3600 and 43200 seconds (AWS IAM limits)."
  }
}

variable "tags" {
  description = "Additional tags merged onto every resource in this module."
  type        = map(string)
  default     = {}
}
