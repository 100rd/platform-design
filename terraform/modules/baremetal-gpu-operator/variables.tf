variable "enabled" {
  description = "Master toggle. When false the module creates nothing (apply-gated default-OFF posture for the WS-A stack)."
  type        = bool
  default     = false
}

variable "namespace" {
  description = "Namespace into which the NVIDIA GPU Operator is installed."
  type        = string
  default     = "gpu-operator"
}

variable "chart_version" {
  description = "Pinned NVIDIA GPU Operator Helm chart version."
  type        = string
  default     = "v24.9.2"
}

variable "chart_repository" {
  description = "Helm repository hosting the gpu-operator chart."
  type        = string
  default     = "https://helm.ngc.nvidia.com/nvidia"
}

variable "driver_enabled" {
  description = "Install the NVIDIA driver via the Operator. MUST stay false on Talos (ADR-0050): the driver ships as a system extension in the boot image; the Operator cannot install it on an immutable, package-manager-less host."
  type        = bool
  default     = false

  validation {
    condition     = var.driver_enabled == false
    error_message = "driver_enabled must be false on bare-metal Talos — the driver ships as a system extension (ADR-0050), not an Operator install."
  }
}

variable "toolkit_enabled" {
  description = "Install the NVIDIA container toolkit via the Operator. Stays false on Talos — the toolkit ships in the system extension (ADR-0050)."
  type        = bool
  default     = false

  validation {
    condition     = var.toolkit_enabled == false
    error_message = "toolkit_enabled must be false on bare-metal Talos — the toolkit ships as a system extension (ADR-0050)."
  }
}

variable "dra_enabled" {
  description = "Enable the NVIDIA DRA driver for fine-grained / fractional GPU allocation. Composes with baremetal-gpu-scheduling's DeviceClass/ResourceClaimTemplate."
  type        = bool
  default     = true
}

variable "dcgm_exporter_enabled" {
  description = "Enable the Operator's bundled DCGM exporter. Keep false — DCGM is deployed by the dedicated baremetal-gpu-dcgm module."
  type        = bool
  default     = false
}

variable "gpu_node_selector" {
  description = "Node selector identifying GPU nodes the operator components run on. Defaults to the talos-machineconfig GPU-present label."
  type        = map(string)
  default     = { "nvidia.com/gpu.present" = "true" }
  nullable    = false
}

variable "operator_cpu_limit" {
  description = "CPU limit for the operator controller pod."
  type        = string
  default     = "500m"
}

variable "operator_memory_limit" {
  description = "Memory limit for the operator controller pod."
  type        = string
  default     = "512Mi"
}

variable "helm_timeout" {
  description = "Helm release timeout in seconds."
  type        = number
  default     = 600
}

variable "platform_labels" {
  description = "ADR-0028 Kubernetes-plane labels (dotted keys, e.g. platform.system = ml-infra) applied to the namespace and operator workloads."
  type        = map(string)
  default     = {}
  nullable    = false
}
