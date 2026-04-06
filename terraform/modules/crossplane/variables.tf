variable "chart_version" {
  description = "Crossplane Helm chart version"
  type        = string
  default     = "2.2.0"
}

variable "provider_aws_version" {
  description = "Crossplane provider-family-aws version"
  type        = string
  default     = "2.5.0"
}

variable "crossplane_memory_limit" {
  description = "Memory limit for Crossplane pod"
  type        = string
  default     = "2Gi"
}

variable "crossplane_cpu_limit" {
  description = "CPU limit for Crossplane pod"
  type        = string
  default     = "1"
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
