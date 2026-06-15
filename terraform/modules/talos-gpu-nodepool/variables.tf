variable "enabled" {
  description = "Master toggle. When false the module creates nothing (apply-gated default-OFF posture for the WS-A stack)."
  type        = bool
  default     = false
}

variable "pool_name" {
  description = "Logical name of the fixed-capacity GPU node pool (e.g. h100-training, h200-serving)."
  type        = string
  default     = "h100-training"
}

variable "gpu_model" {
  description = "GPU model backing this pool (e.g. H100, H200, L40S). Surfaced as a node label and into DRA device-class selection downstream."
  type        = string
  default     = "H100"
}

variable "namespace" {
  description = "Namespace the node-pool policy ConfigMap is created in."
  type        = string
  default     = "kube-system"
}

variable "machines" {
  description = "Fixed set of bare-metal machines in this pool. Capacity is fixed (ADR-0054: no autoscaler) — the list length IS the pool size. bootstrap_secret is only used when manage_cluster_api = true."
  type = list(object({
    name             = string
    bootstrap_secret = optional(string, "")
  }))
  default  = []
  nullable = false
}

variable "gpu_taint_key" {
  description = "Taint key applied to GPU nodes so only GPU workloads schedule there."
  type        = string
  default     = "nvidia.com/gpu"
}

variable "gpu_taint_value" {
  description = "Taint value for the GPU node taint."
  type        = string
  default     = "present"
}

variable "gpu_taint_effect" {
  description = "Taint effect for the GPU node taint."
  type        = string
  default     = "NoSchedule"

  validation {
    condition     = contains(["NoSchedule", "PreferNoSchedule", "NoExecute"], var.gpu_taint_effect)
    error_message = "gpu_taint_effect must be one of NoSchedule, PreferNoSchedule, NoExecute."
  }
}

variable "manage_cluster_api" {
  description = "Drive Cluster-API (Metal³/Sidero) Machine objects for re-image-based node lifecycle (ADR-0054). Default false → static, pre-provisioned pool; nothing reconciles real hardware. Apply-gated."
  type        = bool
  default     = false
}

variable "cluster_api_infra_provider" {
  description = "Cluster-API infrastructure provider for the re-image path (ADR-0054). sidero is the recommended Talos-native default; metal3 (Ironic/PXE) is the alternative."
  type        = string
  default     = "sidero"

  validation {
    condition     = contains(["sidero", "metal3"], var.cluster_api_infra_provider)
    error_message = "cluster_api_infra_provider must be one of sidero, metal3."
  }
}

variable "cluster_api_namespace" {
  description = "Namespace the Cluster-API Machine objects live in (when manage_cluster_api = true)."
  type        = string
  default     = "cluster-api"
}

variable "cluster_name" {
  description = "Cluster name the Cluster-API Machines belong to (per-DC)."
  type        = string
  default     = "uk-baremetal-gpu"
}

variable "platform_labels" {
  description = "ADR-0028 dotted platform labels (e.g. platform.system = ml-infra) applied to every object and node label set."
  type        = map(string)
  default     = {}
  nullable    = false
}
