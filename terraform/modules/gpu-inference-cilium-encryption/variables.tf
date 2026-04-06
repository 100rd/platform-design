variable "operator_replicas" {
  description = "Number of Cilium operator replicas for HA"
  type        = number
  default     = 3
}

variable "k8s_api_qps" {
  description = "Kubernetes API QPS for Cilium operator"
  type        = number
  default     = 50
}

variable "k8s_api_burst" {
  description = "Kubernetes API burst for Cilium operator"
  type        = number
  default     = 100
}

variable "agent_cpu_limit" {
  description = "CPU limit for Cilium agent"
  type        = string
  default     = "2"
}

variable "agent_memory_limit" {
  description = "Memory limit for Cilium agent"
  type        = string
  default     = "2Gi"
}

variable "agent_cpu_request" {
  description = "CPU request for Cilium agent"
  type        = string
  default     = "500m"
}

variable "agent_memory_request" {
  description = "Memory request for Cilium agent"
  type        = string
  default     = "512Mi"
}

variable "exclude_nccl_from_encryption" {
  description = "Exclude NCCL traffic from WireGuard encryption for max training performance"
  type        = bool
  default     = false
}

variable "nccl_port_range" {
  description = "NCCL port range to exclude from encryption"
  type        = list(number)
  default     = [5000, 5001, 5002, 5003, 5004, 5005]
}

variable "enable_prometheus_alerts" {
  description = "Enable Prometheus alerting rules for Cilium"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
