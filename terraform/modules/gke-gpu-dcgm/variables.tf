variable "enabled" {
  description = "Master toggle. When false the module creates nothing."
  type        = bool
  default     = true
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
  description = "Scrape interval hint embedded in the ServiceMonitor/scrape annotations."
  type        = string
  default     = "15s"
}

variable "create_service_monitor" {
  description = "Create a Prometheus-Operator ServiceMonitor (true) for Prometheus/VictoriaMetrics scrape. When the metrics backend uses plain pod annotations, set false."
  type        = bool
  default     = true
}

variable "service_monitor_release_label" {
  description = "Value of the `release` label the ServiceMonitor carries so the Prometheus/VictoriaMetrics operator selects it."
  type        = string
  default     = "victoria-metrics"
}

variable "gpu_node_selector" {
  description = "Node selector restricting the DaemonSet to GPU nodes. Defaults to the GKE accelerator label key (any value)."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "helm_timeout" {
  description = "Helm release timeout in seconds."
  type        = number
  default     = 300
}

variable "platform_labels" {
  description = "ADR-0028 Kubernetes-plane labels (dotted keys, e.g. platform.system = ml-infra) applied to the namespace and exporter workloads."
  type        = map(string)
  default     = {}
  nullable    = false
}
