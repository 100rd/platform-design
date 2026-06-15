# ---------------------------------------------------------------------------------------------------------------------
# aws-eks-gpu-dcgm — DCGM Exporter + GPU-health auto-taint + alert rules (ADR-0044 D1)
# ---------------------------------------------------------------------------------------------------------------------

variable "enabled" {
  description = "Master toggle. When false the module creates nothing (default-OFF; apply-gated)."
  type        = bool
  default     = false
  nullable    = false
}

variable "namespace" {
  description = "Namespace for the DCGM exporter."
  type        = string
  default     = "gpu-monitoring"
}

variable "chart_version" {
  description = "Pinned NVIDIA dcgm-exporter Helm chart version (no main/latest)."
  type        = string
  default     = "4.2.3"
}

variable "chart_repository" {
  description = "Helm repository hosting the dcgm-exporter chart."
  type        = string
  default     = "https://nvidia.github.io/dcgm-exporter/helm-charts"
}

variable "exporter_port" {
  description = "Port the DCGM exporter serves metrics on."
  type        = number
  default     = 9400
}

variable "metrics_backend" {
  description = "Metrics stack the exporter targets (ADR-0026): prometheus or victoriametrics. Selects the ServiceMonitor release label convention."
  type        = string
  default     = "prometheus"

  validation {
    condition     = contains(["prometheus", "victoriametrics"], var.metrics_backend)
    error_message = "metrics_backend must be 'prometheus' or 'victoriametrics'."
  }
}

variable "create_service_monitor" {
  description = "Render a Prometheus-Operator ServiceMonitor from the chart (keeps the module free of kubernetes_manifest, which needs a live cluster at plan time)."
  type        = bool
  default     = true
  nullable    = false
}

variable "service_monitor_release_label" {
  description = "The `release` label the metrics backend selects ServiceMonitors by."
  type        = string
  default     = "kube-prometheus-stack"
}

variable "scrape_interval" {
  description = "ServiceMonitor scrape interval."
  type        = string
  default     = "30s"
}

variable "enable_auto_taint" {
  description = "Deploy the GPU-health auto-taint CronJob that taints nodes with XID/ECC errors (ADR-0044 D1)."
  type        = bool
  default     = true
  nullable    = false
}

variable "xid_error_threshold" {
  description = "XID error count above which a node is auto-tainted."
  type        = number
  default     = 1
}

variable "temperature_threshold" {
  description = "GPU temperature (C) above which an alert fires."
  type        = number
  default     = 85
}

variable "taint_cron_schedule" {
  description = "Cron schedule for the auto-taint health check."
  type        = string
  default     = "*/5 * * * *"
}

variable "kubectl_image" {
  description = "Image used by the auto-taint CronJob to taint nodes."
  type        = string
  default     = "bitnami/kubectl:1.34"
}

# -------------------------------------------------------------------------
# Auto-taint CronJob container resources (hardening)
# The CronJob only runs `kubectl patch` on nodes, so the footprint is tiny.
# memory request == limit (no overcommit); CPU stays burstable (no CPU limit)
# so a short-lived patch is not throttled. Override per-env if needed.
# -------------------------------------------------------------------------

variable "taint_cpu_request" {
  description = "CPU request for the auto-taint CronJob container (Kubernetes quantity, e.g. '50m'). Small by design — the job only runs kubectl patch."
  type        = string
  default     = "50m"
}

variable "taint_memory_request" {
  description = "Memory request for the auto-taint CronJob container (Kubernetes quantity, e.g. '64Mi')."
  type        = string
  default     = "64Mi"
}

variable "taint_memory_limit" {
  description = "Memory limit for the auto-taint CronJob container (Kubernetes quantity, e.g. '128Mi'). Caps the container so a wedged probe cannot starve the node."
  type        = string
  default     = "128Mi"
}

variable "gpu_node_selector" {
  description = "Node selector identifying GPU nodes the exporter DaemonSet runs on."
  type        = map(string)
  default     = { "karpenter.sh/nodepool" = "gpu" }
  nullable    = false
}

variable "helm_timeout" {
  description = "Helm release timeout in seconds."
  type        = number
  default     = 600
}

variable "platform_labels" {
  description = "ADR-0028 Kubernetes-plane labels (dotted keys) on the namespace + exporter/cronjob workloads."
  type        = map(string)
  default     = {}
  nullable    = false
}
