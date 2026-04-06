variable "reserved_system_cpus" {
  description = "CPU cores reserved for system processes (e.g., 0-3)"
  type        = string
  default     = "0-3"
}

variable "isolated_cpus" {
  description = "CPU cores isolated for workloads (e.g., 4-191 for p5.48xlarge)"
  type        = string
  default     = "4-191"
}

variable "hugepage_size" {
  description = "HugePages size (1G or 2M)"
  type        = string
  default     = "1G"
}

variable "hugepages_count" {
  description = "Number of hugepages to allocate"
  type        = number
  default     = 1536
}

variable "kube_reserved_cpu" {
  description = "CPU reserved for kubelet"
  type        = string
  default     = "2"
}

variable "kube_reserved_memory" {
  description = "Memory reserved for kubelet"
  type        = string
  default     = "4Gi"
}

variable "system_reserved_cpu" {
  description = "CPU reserved for system daemons"
  type        = string
  default     = "2"
}

variable "system_reserved_memory" {
  description = "Memory reserved for system daemons"
  type        = string
  default     = "4Gi"
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
