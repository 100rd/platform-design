# ---------------------------------------------------------------------------------------------------------------------
# GPU Inference DCGM Exporter — Variables
# ---------------------------------------------------------------------------------------------------------------------

variable "dcgm_exporter_version" {
  description = "DCGM Exporter Helm chart version (maps to dcgm-exporter image tag)"
  type        = string
  default     = "4.5.0"
}

variable "namespace" {
  description = "Kubernetes namespace for DCGM Exporter resources"
  type        = string
  default     = "gpu-monitoring"
}

variable "enable_auto_taint" {
  description = "Enable automatic node tainting when GPU health checks fail (XID errors exceed threshold)"
  type        = bool
  default     = true
}

variable "xid_error_threshold" {
  description = "Number of XID errors per GPU per minute that triggers node taint"
  type        = number
  default     = 1
}

variable "temperature_threshold" {
  description = "GPU temperature in Celsius above which a high-temperature alert fires"
  type        = number
  default     = 85
}

variable "scrape_interval" {
  description = "Prometheus/VictoriaMetrics scrape interval for DCGM metrics"
  type        = string
  default     = "15s"
}

variable "service_account_name" {
  description = "ServiceAccount name for the DCGM Exporter DaemonSet"
  type        = string
  default     = "dcgm-exporter"
}

variable "auto_taint_service_account_name" {
  description = "ServiceAccount name for the GPU health auto-taint CronJob"
  type        = string
  default     = "gpu-health-tainter"
}

variable "kubectl_image" {
  description = "Container image used by the auto-taint CronJob to run kubectl"
  type        = string
  default     = "bitnami/kubectl:1.30"
}

variable "taint_cron_schedule" {
  description = "Cron schedule for the GPU health tainting job"
  type        = string
  default     = "*/2 * * * *"
}

variable "alert_namespace" {
  description = "Namespace where PrometheusRule / VMRule CRDs are installed"
  type        = string
  default     = "monitoring"
}

variable "use_vm_rule" {
  description = "When true deploy a VMRule (VictoriaMetrics); when false deploy a PrometheusRule"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags to apply to namespace and other label-able resources"
  type        = map(string)
  default     = {}
}
