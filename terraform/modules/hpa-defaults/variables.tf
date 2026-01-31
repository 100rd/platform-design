variable "enabled" {
  description = "Whether to create HPA defaults for platform components"
  type        = bool
  default     = false
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}
