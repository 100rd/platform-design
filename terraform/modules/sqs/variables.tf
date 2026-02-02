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
