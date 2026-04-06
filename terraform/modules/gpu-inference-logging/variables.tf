variable "vector_version" {
  description = "Vector Helm chart version"
  type        = string
  default     = "0.54.0"
}

variable "clickhouse_version" {
  description = "ClickHouse Helm chart version"
  type        = string
  default     = "26.3.0"
}

variable "clickhouse_replicas" {
  description = "Number of ClickHouse StatefulSet replicas"
  type        = number
  default     = 3
}

variable "storage_size" {
  description = "PersistentVolumeClaim size for each ClickHouse replica"
  type        = string
  default     = "500Gi"
}

variable "retention_days" {
  description = "Log retention period in days for ClickHouse TTL"
  type        = number
  default     = 30
}

variable "vector_namespace" {
  description = "Kubernetes namespace for Vector DaemonSet"
  type        = string
  default     = "logging"
}

variable "clickhouse_namespace" {
  description = "Kubernetes namespace for ClickHouse StatefulSet"
  type        = string
  default     = "logging"
}

variable "clickhouse_password" {
  description = "ClickHouse default user password"
  type        = string
  sensitive   = true
}

variable "tags" {
  description = "Tags to apply to Kubernetes resources as labels"
  type        = map(string)
  default     = {}
}
