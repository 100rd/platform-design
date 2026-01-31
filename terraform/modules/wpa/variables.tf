variable "enabled" {
  description = "Whether to deploy the WPA controller"
  type        = bool
  default     = false
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "wpa_version" {
  description = "WPA Helm chart version"
  type        = string
  default     = "0.7.1"
}

variable "namespace" {
  description = "Kubernetes namespace for WPA"
  type        = string
  default     = "kube-system"
}

variable "controller_replicas" {
  description = "Number of WPA controller replicas"
  type        = number
  default     = 1
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
