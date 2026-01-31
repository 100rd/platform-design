variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace for KEDA"
  type        = string
  default     = "kube-system"
}

variable "keda_version" {
  description = "KEDA Helm chart version"
  type        = string
  default     = "2.16.1"
}

variable "operator_replicas" {
  description = "Number of KEDA operator replicas"
  type        = number
  default     = 1
}

variable "metrics_server_replicas" {
  description = "Number of KEDA metrics server replicas"
  type        = number
  default     = 1
}

variable "enable_prometheus_metrics" {
  description = "Enable Prometheus metrics for KEDA"
  type        = bool
  default     = true
}

variable "log_level" {
  description = "Log level for KEDA operator"
  type        = string
  default     = "info"
  validation {
    condition     = contains(["debug", "info", "warn", "error"], var.log_level)
    error_message = "Log level must be one of: debug, info, warn, error"
  }
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
