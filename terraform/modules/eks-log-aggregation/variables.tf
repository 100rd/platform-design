variable "cluster_name" {
  description = "EKS cluster name. Used to derive the source CloudWatch log group (`/aws/eks/<name>/cluster`) and to namespace resource names."
  type        = string
}

variable "aws_region" {
  description = "AWS region of the EKS cluster."
  type        = string
}

variable "log_group_retention_days" {
  description = "Retention for the source CloudWatch log group. PCI-DSS Req 10.7 requires at least 1 year. Long-term retention happens in S3 (centralized-logging module #182)."
  type        = number
  default     = 90
  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_group_retention_days)
    error_message = "log_group_retention_days must be one of CloudWatch's allowed retention values."
  }
}

variable "destination_s3_bucket_arn" {
  description = "ARN of the centralized log-archive S3 bucket (provisioned by terraform/modules/centralized-logging in the log-archive account)."
  type        = string
}

variable "destination_s3_prefix" {
  description = "Prefix in the destination bucket where audit + authenticator logs land. Maps to the eks-audit / eks-authenticator entries in centralized-logging.log_source_prefixes."
  type        = string
  default     = "eks-audit"
}

variable "destination_kms_key_arn" {
  description = "ARN of the KMS key on the destination S3 bucket (consumed by Firehose for SSE-KMS during write)."
  type        = string
}

variable "log_streams_to_forward" {
  description = "Subset of EKS control-plane log streams to forward to the central bucket. Defaults to audit + authenticator (the security-critical ones)."
  type        = list(string)
  default     = ["kube-apiserver-audit", "authenticator"]
}

variable "firehose_buffer_seconds" {
  description = "Firehose buffer interval. Trade off between near-real-time (60s) and write-cost (300s)."
  type        = number
  default     = 60
}

variable "firehose_buffer_size_mb" {
  description = "Firehose buffer size in MB. Together with buffer_seconds determines flush cadence."
  type        = number
  default     = 5
}

variable "tags" {
  description = "Tags to apply to all resources."
  type        = map(string)
  default     = {}
}
