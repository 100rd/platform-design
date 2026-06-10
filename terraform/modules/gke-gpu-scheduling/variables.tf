variable "enabled" {
  description = "Master toggle. When false the module creates nothing (cluster uses the default kube-scheduler)."
  type        = bool
  default     = true
}

variable "scheduler" {
  description = "Batch scheduler to deploy. ADR-0036 selected Volcano for WS-A (native gang scheduling for distributed training + parity with the EKS gpu-inference-volcano stack), so volcano is the default; kueue remains selectable."
  type        = string
  default     = "volcano"

  validation {
    condition     = contains(["kueue", "volcano"], var.scheduler)
    error_message = "scheduler must be one of: kueue, volcano."
  }
}

variable "namespace" {
  description = "Namespace into which the batch scheduler is installed."
  type        = string
  default     = "gpu-batch-scheduling"
}

variable "kueue_chart_version" {
  description = "Pinned Kueue Helm chart version."
  type        = string
  default     = "0.9.1"
}

variable "kueue_chart_repository" {
  description = "Helm OCI/HTTP repository hosting the Kueue chart."
  type        = string
  default     = "oci://registry.k8s.io/kueue/charts"
}

variable "volcano_chart_version" {
  description = "Pinned Volcano Helm chart version (used when scheduler = volcano)."
  type        = string
  default     = "1.10.0"
}

variable "volcano_chart_repository" {
  description = "Helm repository hosting the Volcano chart."
  type        = string
  default     = "https://volcano-sh.github.io/helm-charts"
}

variable "manage_gpu_taints" {
  description = "Whether the scheduler should tolerate the nvidia.com/gpu taint for its controller components."
  type        = bool
  default     = true
}

variable "helm_timeout" {
  description = "Helm release timeout in seconds."
  type        = number
  default     = 300
}

variable "platform_labels" {
  description = "ADR-0028 Kubernetes-plane labels (dotted keys, e.g. platform.system = ml-infra) applied to the namespace and scheduler workloads."
  type        = map(string)
  default     = {}
  nullable    = false
}
