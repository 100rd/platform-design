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
  description = "Kubernetes namespace of the ESO controller ServiceAccount. Defaults to 'external-secrets'. Drives the ABAC kubernetes-namespace policy condition."
  type        = string
  default     = "external-secrets"
  nullable    = false
}

variable "service_account" {
  description = "Kubernetes ServiceAccount name bound to the Pod Identity role. Defaults to 'external-secrets' (the ESO chart's controller SA). ESO uses THIS identity, never serviceAccountRef."
  type        = string
  default     = "external-secrets"
  nullable    = false
}

variable "secret_arn_patterns" {
  description = "List of Secrets Manager ARN patterns ESO may read/write. Empty list (default) means all secrets ('*'); pass a path-prefixed ARN pattern to narrow (e.g. ['arn:aws:secretsmanager:*:*:secret:/platform/*'])."
  type        = list(string)
  default     = []
  nullable    = false
}

variable "kms_key_arns" {
  description = "List of KMS CMK ARNs ESO may decrypt/encrypt (the keys protecting the managed secrets). Empty list (default) means all keys ('*'); pin to the platform secrets CMK in production."
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
  description = "Maximum IAM role session duration in seconds. Pod Identity caches assumed credentials, so the default 3600s (1h) is sufficient for ESO's reconcile loop."
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
