variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "vmselect_url" {
  description = "VictoriaMetrics vmselect HTTP URL (e.g. http://vmselect.monitoring.svc:8481/select/0/prometheus)"
  type        = string
}

variable "prometheus_adapter_version" {
  description = "Helm chart version for prometheus-community/prometheus-adapter"
  type        = string
  default     = "4.11.0"
}

variable "adapter_namespace" {
  description = "Kubernetes namespace where Prometheus Adapter is installed"
  type        = string
  default     = "monitoring"
}

variable "adapter_replicas" {
  description = "Number of Prometheus Adapter replicas"
  type        = number
  default     = 2
}

variable "vllm_namespace" {
  description = "Kubernetes namespace where the vLLM deployment runs"
  type        = string
  default     = "gpu-inference"
}

variable "vllm_deployment_name" {
  description = "Name of the vLLM Deployment to scale"
  type        = string
  default     = "vllm"
}

variable "min_replicas" {
  description = "Minimum number of vLLM replicas"
  type        = number
  default     = 2
}

variable "max_replicas" {
  description = "Maximum number of vLLM replicas"
  type        = number
  default     = 50
}

variable "queue_depth_target" {
  description = "Target value for vllm_requests_waiting metric (avg per pod)"
  type        = number
  default     = 5
}

variable "cache_usage_target" {
  description = "Target gpu_cache_usage_perc (percentage, e.g. 80)"
  type        = number
  default     = 80
}
