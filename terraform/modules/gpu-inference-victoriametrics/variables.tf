variable "operator_chart_version" {
  description = "VictoriaMetrics Operator Helm chart version"
  type        = string
  default     = "0.59.3"
}

variable "retention_period" {
  description = "Metrics retention period (e.g. 30d, 90d)"
  type        = string
  default     = "30d"
}

variable "vminsert_replicas" {
  description = "Number of vminsert replicas for ingestion scaling"
  type        = number
  default     = 3
}

variable "vmselect_replicas" {
  description = "Number of vmselect replicas for query scaling"
  type        = number
  default     = 3
}

variable "vmstorage_replicas" {
  description = "Number of vmstorage replicas for storage HA"
  type        = number
  default     = 3
}

variable "storage_class" {
  description = "Kubernetes StorageClass for vmstorage PVCs"
  type        = string
  default     = "gp3"
}

variable "storage_size" {
  description = "Storage size per vmstorage replica"
  type        = string
  default     = "500Gi"
}

variable "tags" {
  description = "Tags to apply to cloud resources"
  type        = map(string)
  default     = {}
}
