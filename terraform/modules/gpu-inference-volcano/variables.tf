variable "chart_version" {
  description = "Volcano Helm chart version"
  type        = string
  default     = "1.8.2"
}

variable "scheduler_replicas" {
  description = "Number of Volcano scheduler replicas"
  type        = number
  default     = 2
}

variable "controller_replicas" {
  description = "Number of Volcano controller replicas"
  type        = number
  default     = 2
}

variable "training_queue_weight" {
  description = "Weight for training queue (higher = more resources)"
  type        = number
  default     = 10
}

variable "inference_queue_weight" {
  description = "Weight for inference queue"
  type        = number
  default     = 5
}

variable "batch_queue_weight" {
  description = "Weight for batch processing queue"
  type        = number
  default     = 2
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}
