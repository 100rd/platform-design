variable "name" {
  description = "Name for the EventBridge rule"
  type        = string
}

variable "source_bucket_name" {
  description = "Name of the S3 bucket to watch for ObjectCreated events"
  type        = string
}

variable "source_bucket_arn" {
  description = "ARN of the source S3 bucket (used for documentation and potential future IAM policies)"
  type        = string
}

variable "target_queue_arn" {
  description = "ARN of the SQS queue to receive event messages"
  type        = string
}

variable "target_queue_url" {
  description = "URL of the SQS queue (required for the queue policy resource)"
  type        = string
}

variable "event_pattern_suffix" {
  description = "List of file suffixes to match in S3 ObjectCreated events"
  type        = list(string)
  default     = [".mp4", ".avi", ".mov", ".mkv"]
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
