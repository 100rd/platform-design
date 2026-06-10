variable "enabled" {
  description = "Master toggle. When false the module creates nothing (useful for clusters that rely on the GKE-managed GPU driver instead)."
  type        = bool
  default     = true
}

variable "namespace" {
  description = "Namespace into which the NVIDIA GPU Operator is installed."
  type        = string
  default     = "gpu-operator"
}

variable "chart_version" {
  description = "Pinned NVIDIA GPU Operator Helm chart version. Pin explicitly per environment for reproducible installs."
  type        = string
  default     = "v24.9.2"
}

variable "chart_repository" {
  description = "Helm repository hosting the gpu-operator chart."
  type        = string
  default     = "https://helm.ngc.nvidia.com/nvidia"
}

variable "driver_enabled" {
  description = "Install the NVIDIA driver via the operator. Set false on GKE when using GKE-managed GPU drivers (default for GKE Standard with COS)."
  type        = bool
  default     = false
}

variable "toolkit_enabled" {
  description = "Install the NVIDIA container toolkit via the operator. Set false on GKE (COS ships the toolkit)."
  type        = bool
  default     = false
}

variable "dcgm_exporter_enabled" {
  description = "Enable the operator's bundled DCGM exporter. Keep false — DCGM is deployed by the dedicated gke-gpu-dcgm module."
  type        = bool
  default     = false
}

variable "gpu_node_selector" {
  description = "Node selector identifying GPU nodes the operator components should run on. Defaults to the GKE accelerator label."
  type        = map(string)
  default     = { "cloud.google.com/gke-accelerator" = "nvidia-l4" }
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
  description = "ADR-0028 Kubernetes-plane labels (dotted keys, e.g. platform.system = ml-infra) applied to the namespace and propagated to operator workloads."
  type        = map(string)
  default     = {}
  nullable    = false
}
