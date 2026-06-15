# ---------------------------------------------------------------------------------------------------------------------
# aws-eks-gpu-operator — NVIDIA GPU Operator on EKS (ADR-0044 D1)
# ---------------------------------------------------------------------------------------------------------------------

variable "enabled" {
  description = "Master toggle. When false the module creates nothing (default-OFF; apply-gated)."
  type        = bool
  default     = false
  nullable    = false
}

variable "namespace" {
  description = "Namespace into which the NVIDIA GPU Operator is installed."
  type        = string
  default     = "gpu-operator"
}

variable "chart_version" {
  description = "Pinned NVIDIA GPU Operator Helm chart version. Pin explicitly per environment (no main/latest)."
  type        = string
  default     = "v25.3.0"
}

variable "chart_repository" {
  description = "Helm repository hosting the gpu-operator chart."
  type        = string
  default     = "https://helm.ngc.nvidia.com/nvidia"
}

variable "node_os" {
  description = "Node OS for GPU pools. On 'bottlerocket' (ADR-0030 default) the NVIDIA driver/toolkit are pre-baked into the GPU AMI so driver_enabled is forced false; on 'al2023' the operator installs the driver (ADR-0044 D1)."
  type        = string
  default     = "bottlerocket"

  validation {
    condition     = contains(["bottlerocket", "al2023"], var.node_os)
    error_message = "node_os must be 'bottlerocket' or 'al2023'."
  }
}

variable "driver_enabled" {
  description = "Override: install the NVIDIA driver via the operator. Null derives from node_os (false on Bottlerocket pre-baked AMI, true on AL2023) per ADR-0044 D1."
  type        = bool
  default     = null
}

variable "dra_driver_enabled" {
  description = "Enable the NVIDIA DRA driver (publishes ResourceSlices for typed GPU requests, ADR-0044 D2). The whole point of using the operator over the plain device plugin."
  type        = bool
  default     = true
  nullable    = false
}

variable "dcgm_exporter_enabled" {
  description = "Enable the operator's bundled DCGM exporter. Keep false — DCGM is owned by aws-eks-gpu-dcgm (ADR-0044 D1)."
  type        = bool
  default     = false
  nullable    = false
}

variable "gpu_node_selector" {
  description = "Node selector identifying GPU nodes the operator components run on (Karpenter nodepool label or managed node-group GPU label)."
  type        = map(string)
  default     = { "karpenter.sh/nodepool" = "gpu" }
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
  description = "ADR-0028 Kubernetes-plane labels (dotted keys, e.g. platform.system = ml-platform) applied to the namespace and propagated to operator workloads."
  type        = map(string)
  default     = {}
  nullable    = false
}
