variable "enabled" {
  description = "Master toggle. When false the module creates nothing (apply-gated default-OFF posture for the WS-A stack)."
  type        = bool
  default     = false
}

variable "namespace" {
  description = "Namespace into which the DCGM exporter DaemonSet is installed."
  type        = string
  default     = "gpu-monitoring"
}

variable "chart_version" {
  description = "Pinned dcgm-exporter Helm chart version."
  type        = string
  default     = "3.6.1"
}

variable "chart_repository" {
  description = "Helm repository hosting the dcgm-exporter chart."
  type        = string
  default     = "https://nvidia.github.io/dcgm-exporter/helm-charts"
}

variable "exporter_port" {
  description = "Container/service port the DCGM exporter listens on for metrics scraping."
  type        = number
  default     = 9400
}

variable "scrape_interval" {
  description = "Scrape interval hint embedded in the ServiceMonitor."
  type        = string
  default     = "15s"
}

variable "create_service_monitor" {
  description = "Create a Prometheus-Operator ServiceMonitor for VictoriaMetrics/Prometheus scrape."
  type        = bool
  default     = true
}

variable "service_monitor_release_label" {
  description = "Value of the `release` label the ServiceMonitor carries so the metrics operator selects it."
  type        = string
  default     = "victoria-metrics"
}

variable "gpu_node_selector" {
  description = "Node selector restricting the DaemonSet to GPU nodes. Defaults to the talos-machineconfig GPU-present label."
  type        = map(string)
  default     = { "nvidia.com/gpu.present" = "true" }
  nullable    = false
}

variable "enable_auto_taint" {
  description = "Deploy the GPU-health auto-taint CronJob that taints a node out of scheduling on an XID-error burst (ports gpu-inference-dcgm; honours gpu-driver-updates.md)."
  type        = bool
  default     = true
}

variable "auto_taint_schedule" {
  description = "Cron schedule the GPU-health auto-taint check runs on."
  type        = string
  default     = "*/2 * * * *"
}

variable "auto_taint_image" {
  description = "Container image for the GPU-health auto-taint check job."
  type        = string
  default     = "ghcr.io/example/gpu-health-autotaint:0.1.0"
}

variable "auto_taint_service_account" {
  description = "ServiceAccount the auto-taint CronJob runs as (needs node-taint RBAC, granted by the GitOps layer)."
  type        = string
  default     = "gpu-health-autotaint"
}

variable "xid_error_threshold" {
  description = "Number of XID errors within the window that trips the auto-taint (a simulated XID burst above this taints the node)."
  type        = number
  default     = 3
}

variable "helm_timeout" {
  description = "Helm release timeout in seconds."
  type        = number
  default     = 300
}

variable "platform_labels" {
  description = "ADR-0028 Kubernetes-plane labels (dotted keys, e.g. platform.system = ml-infra) applied to the namespace, exporter, and auto-taint CronJob."
  type        = map(string)
  default     = {}
  nullable    = false
}
