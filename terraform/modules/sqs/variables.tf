variable "name" {
  description = "Name of the SQS queue"
  type        = string
}

variable "visibility_timeout_seconds" {
  description = "Visibility timeout for the queue"
  type        = number
  default     = 30
}

variable "message_retention_seconds" {
  description = "Message retention period in seconds"
  type        = number
  default     = 345600 # 4 days
}

variable "max_message_size" {
  description = "Maximum message size in bytes"
  type        = number
  default     = 262144 # 256 KB
}

variable "delay_seconds" {
  description = "Delay seconds for the queue"
  type        = number
  default     = 0
}

variable "receive_wait_time_seconds" {
  description = "Long polling wait time"
  type        = number
  default     = 10
}

variable "fifo_queue" {
  description = "Whether this is a FIFO queue"
  type        = bool
  default     = false
}

variable "content_based_deduplication" {
  description = "Enable content-based deduplication for FIFO queues"
  type        = bool
  default     = false
}

variable "kms_master_key_id" {
  description = "ARN of the KMS CMK for SQS server-side encryption. When set, KMS encryption is used instead of SQS-managed SSE."
  type        = string
  default     = null
}

variable "kms_data_key_reuse_period_seconds" {
  description = "Duration (in seconds) that SQS can reuse a data key to encrypt/decrypt messages before calling KMS again. Valid range: 60-86400."
  type        = number
  default     = 300

  validation {
    condition     = var.kms_data_key_reuse_period_seconds >= 60 && var.kms_data_key_reuse_period_seconds <= 86400
    error_message = "kms_data_key_reuse_period_seconds must be between 60 and 86400."
  }
}

variable "create_dlq" {
  description = "Create a dead-letter queue"
  type        = bool
  default     = true
}

variable "max_receive_count" {
  description = "Max receive count before sending to DLQ"
  type        = number
  default     = 3
}

variable "dlq_message_retention_seconds" {
  description = "DLQ message retention period"
  type        = number
  default     = 1209600 # 14 days
}

variable "create_iam_policies" {
  description = "Create IAM policies for producer/consumer IRSA"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
