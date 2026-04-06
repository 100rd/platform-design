variable "cluster_name" {
  description = "Name of the EKS cluster (used to tag resources)"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace for the validation suite"
  type        = string
  default     = "gpu-inference-validation"
}

variable "schedule" {
  description = "Cron expression for the periodic validation CronJob"
  type        = string
  default     = "0 2 * * 0" # Weekly on Sunday at 02:00 UTC
}

variable "vllm_server_url" {
  description = "URL of the vLLM inference server to benchmark"
  type        = string
  default     = "http://vllm-server.gpu-inference.svc.cluster.local:8000"
}

variable "victoria_metrics_url" {
  description = "VictoriaMetrics query URL for observability checks"
  type        = string
  default     = "http://victoria-metrics.monitoring.svc.cluster.local:8428"
}

variable "clickhouse_host" {
  description = "ClickHouse host for structured log checks"
  type        = string
  default     = "clickhouse.logging.svc.cluster.local"
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "test_manifests_path" {
  description = "Path on disk to the test YAML manifests directory (used to read file contents into ConfigMap)"
  type        = string
  default     = ""
}
