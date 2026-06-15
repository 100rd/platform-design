variable "enabled" {
  description = "Master toggle. When false the module creates nothing (apply-gated default-OFF posture for the WS-A stack)."
  type        = bool
  default     = false
}

variable "scheduler" {
  description = "Batch scheduler to deploy. Volcano is the WS-A choice (gang scheduling + the UK doc's named queue taxonomy)."
  type        = string
  default     = "volcano"

  validation {
    condition     = contains(["volcano"], var.scheduler)
    error_message = "scheduler must be volcano (the UK doc's named secondary scheduler)."
  }
}

variable "namespace" {
  description = "Namespace into which Volcano + the queues/DRA objects are installed."
  type        = string
  default     = "volcano-system"
}

variable "volcano_chart_version" {
  description = "Pinned Volcano Helm chart version."
  type        = string
  default     = "1.10.0"
}

variable "volcano_chart_repository" {
  description = "Helm repository hosting the Volcano chart."
  type        = string
  default     = "https://volcano-sh.github.io/helm-charts"
}

variable "volcano_queues" {
  description = "Volcano queue taxonomy. Defaults to the EXACT UK taxonomy from 06-uk-datacenters.md: H100 training pool (training-default w100 / training-bootstrap w30 / training-urgent w200 cap 2) + H200 serving pool (serving-vllm w150 / eval-judge w200 / engine-build w80 / batch-rescore w50). capability_jobs is the job-count cap (null = uncapped)."
  type = list(object({
    name            = string
    pool            = string
    weight          = number
    reclaimable     = bool
    capability_jobs = optional(number)
  }))
  default = [
    { name = "training-default", pool = "h100", weight = 100, reclaimable = true },
    { name = "training-bootstrap", pool = "h100", weight = 30, reclaimable = true },
    { name = "training-urgent", pool = "h100", weight = 200, reclaimable = false, capability_jobs = 2 },
    { name = "serving-vllm", pool = "h200", weight = 150, reclaimable = false },
    { name = "eval-judge", pool = "h200", weight = 200, reclaimable = true },
    { name = "engine-build", pool = "h200", weight = 80, reclaimable = true },
    { name = "batch-rescore", pool = "h200", weight = 50, reclaimable = true },
  ]
  nullable = false
}

variable "dra_enabled" {
  description = "Create the DRA DeviceClass / ResourceClaimTemplate objects for fine-grained / fractional GPU allocation."
  type        = bool
  default     = true
}

variable "dra_device_classes" {
  description = "DRA device classes for the GPU models in the fleet (H100/H200/L40S + fractional). product_name matches the NVIDIA device attribute; count is the per-claim device count (1 = whole GPU, fractional handled via MPS/MIG profiles upstream)."
  type = list(object({
    name         = string
    product_name = string
    count        = number
  }))
  default = [
    { name = "gpu-h100", product_name = "NVIDIA H100 80GB HBM3", count = 1 },
    { name = "gpu-h200", product_name = "NVIDIA H200", count = 1 },
    { name = "gpu-l40s", product_name = "NVIDIA L40S", count = 1 },
    { name = "gpu-fractional", product_name = "NVIDIA H100 80GB HBM3", count = 1 },
  ]
  nullable = false
}

variable "helm_timeout" {
  description = "Helm release timeout in seconds."
  type        = number
  default     = 300
}

variable "platform_labels" {
  description = "ADR-0028 Kubernetes-plane labels (dotted keys, e.g. platform.system = ml-infra) applied to the namespace, Volcano workloads, queues, and DRA objects."
  type        = map(string)
  default     = {}
  nullable    = false
}
