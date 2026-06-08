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
  description = "Kubernetes namespace of the Loki ServiceAccount. Defaults to 'observability' (where the loki-stack chart deploys). Drives the ABAC kubernetes-namespace policy condition."
  type        = string
  default     = "observability"
  nullable    = false
}

variable "service_account" {
  description = "Kubernetes ServiceAccount name bound to the Pod Identity role. Defaults to 'loki' (the loki-stack chart's SA)."
  type        = string
  default     = "loki"
  nullable    = false
}

variable "bucket_names" {
  description = "List of S3 bucket names Loki uses for chunks/index/ruler/admin storage. Empty list (default) falls back to '*' so the module plans without a real bucket list; pass the Loki bucket names in production for least-privilege."
  type        = list(string)
  default     = []
  nullable    = false
}

variable "kms_key_arns" {
  description = "List of KMS CMK ARNs for SSE-KMS-encrypted Loki buckets. Empty list (default) means all keys ('*'); pin to the bucket CMK in production."
  type        = list(string)
  default     = []
  nullable    = false
}

variable "aws_partition" {
  description = "AWS partition for ARN construction ('aws', 'aws-us-gov', or 'aws-cn')."
  type        = string
  default     = "aws"
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
  description = "Maximum IAM role session duration in seconds. Pod Identity caches assumed credentials, so the default 3600s (1h) is sufficient for Loki's S3 access."
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
