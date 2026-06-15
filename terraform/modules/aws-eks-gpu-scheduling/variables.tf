# ---------------------------------------------------------------------------------------------------------------------
# aws-eks-gpu-scheduling — Volcano batch scheduler + queues + DRA device classes (ADR-0044 D2/D3)
# ---------------------------------------------------------------------------------------------------------------------

variable "enabled" {
  description = "Master toggle. When false the module creates nothing (default-OFF; apply-gated)."
  type        = bool
  default     = false
  nullable    = false
}

variable "namespace" {
  description = "Namespace for the Volcano scheduler."
  type        = string
  default     = "volcano-system"
}

variable "chart_version" {
  description = "Pinned Volcano Helm chart version (current line with the DRA plugin; no main/latest)."
  type        = string
  default     = "1.12.1"
}

variable "chart_repository" {
  description = "Helm repository hosting the Volcano chart."
  type        = string
  default     = "https://volcano-sh.github.io/helm-charts"
}

variable "scheduler_replicas" {
  description = "Volcano scheduler replica count."
  type        = number
  default     = 2
}

variable "controller_replicas" {
  description = "Volcano controller replica count."
  type        = number
  default     = 2
}

variable "training_queue_weight" {
  description = "Fair-share weight for the training Queue."
  type        = number
  default     = 4
}

variable "inference_queue_weight" {
  description = "Fair-share weight for the inference Queue."
  type        = number
  default     = 4
}

variable "batch_queue_weight" {
  description = "Fair-share weight for the batch Queue."
  type        = number
  default     = 2
}

variable "enable_dra" {
  description = "Enable the Volcano `dra` plugin so GPU (and EFA, via aws-eks-efa-fabric DRA mode) ResourceClaims are gang-scheduled (ADR-0044 D3 / ADR-0045 D3)."
  type        = bool
  default     = true
  nullable    = false
}

variable "device_classes" {
  description = "Map of DRA DeviceClass name => CEL selector expression on device productName (e.g. H100/A100/B200), shipped as kubernetes_manifest DeviceClass objects (ADR-0044 D2). Empty skips DeviceClass creation."
  type        = map(string)
  default = {
    "gpu-h100" = "device.attributes[\"gpu.nvidia.com\"].productName == \"NVIDIA-H100-80GB-HBM3\""
    "gpu-a100" = "device.attributes[\"gpu.nvidia.com\"].productName == \"NVIDIA-A100-80GB-PCIe\""
    "gpu-b200" = "device.attributes[\"gpu.nvidia.com\"].productName == \"NVIDIA-B200\""
  }
  nullable = false
}

variable "resource_claim_templates" {
  description = "Map of ResourceClaimTemplate name => the DeviceClass it requests (single-GPU / full-node NVLink island / MIG slice). Empty skips template creation."
  type        = map(string)
  default = {
    "single-gpu-h100" = "gpu-h100"
    "single-gpu-a100" = "gpu-a100"
  }
  nullable = false
}

variable "dra_namespace" {
  description = "Namespace the ResourceClaimTemplates live in (workload namespace). DeviceClasses are cluster-scoped."
  type        = string
  default     = "default"
}

variable "manage_gpu_taints" {
  description = "Tolerate the nvidia.com/gpu taint on the scheduler/controller pods."
  type        = bool
  default     = false
  nullable    = false
}

variable "helm_timeout" {
  description = "Helm release timeout in seconds."
  type        = number
  default     = 600
}

variable "platform_labels" {
  description = "ADR-0028 Kubernetes-plane labels (dotted keys) on the namespace + scheduler workloads + DRA objects."
  type        = map(string)
  default     = {}
  nullable    = false
}
