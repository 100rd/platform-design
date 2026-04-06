variable "chart_version" {
  description = "NVIDIA GPU Operator Helm chart version"
  type        = string
  default     = "v26.3.0"
}

variable "dra_driver_version" {
  description = "NVIDIA DRA driver version"
  type        = string
  default     = "v25.3.0"
}

variable "driver_enabled" {
  description = "Enable NVIDIA driver installation (false if pre-installed in AMI)"
  type        = bool
  default     = false
}

variable "dcgm_exporter_enabled" {
  description = "Enable DCGM Exporter (deployed separately in Phase 5)"
  type        = bool
  default     = false
}

variable "operator_cpu_limit" {
  description = "CPU limit for GPU Operator"
  type        = string
  default     = "500m"
}

variable "operator_memory_limit" {
  description = "Memory limit for GPU Operator"
  type        = string
  default     = "512Mi"
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
