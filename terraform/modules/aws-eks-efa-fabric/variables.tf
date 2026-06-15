# ---------------------------------------------------------------------------------------------------------------------
# aws-eks-efa-fabric — EFA exposure, per-provisioner (ADR-0045 D2/D3/D4)
# ---------------------------------------------------------------------------------------------------------------------

variable "enabled" {
  description = "Master toggle. When false the module creates nothing (default-OFF; apply-gated)."
  type        = bool
  default     = false
  nullable    = false
}

variable "mode" {
  description = <<-EOT
    EFA exposure mode (ADR-0045 D4):
      * "device-plugin" → aws-efa-k8s-device-plugin DaemonSet; pods request
        vpc.amazonaws.com/efa. The ONLY valid mode under Karpenter (ADR-0045 D2).
      * "dra" → EFA DRA driver + a netdev DeviceClass/ResourceClaimTemplate; valid
        ONLY on managed node groups (ADR-0045 D3). The stack derives this from the
        pool's provisioner (ADR-0046), never set independently.
  EOT
  type        = string
  default     = "device-plugin"

  validation {
    condition     = contains(["device-plugin", "dra"], var.mode)
    error_message = "mode must be 'device-plugin' or 'dra'."
  }
}

variable "provisioner" {
  description = "The node provisioner the fabric is being attached to: 'karpenter' or 'managed-node-group'. Used to assert mode = dra only on managed node groups (ADR-0045 D2/D3, ADR-0046)."
  type        = string
  default     = "karpenter"

  validation {
    condition     = contains(["karpenter", "managed-node-group"], var.provisioner)
    error_message = "provisioner must be 'karpenter' or 'managed-node-group'."
  }
}

variable "cluster_name" {
  description = "EKS cluster name the fabric is installed on."
  type        = string
}

variable "namespace" {
  description = "Namespace for the EFA device plugin / DRA objects."
  type        = string
  default     = "kube-system"
}

variable "efa_device_plugin_version" {
  description = "Pinned aws-efa-k8s-device-plugin Helm chart version (device-plugin mode; no main/latest)."
  type        = string
  default     = "v0.5.7"
}

variable "efa_device_plugin_repository" {
  description = "Helm repository hosting the aws-efa-k8s-device-plugin chart."
  type        = string
  default     = "https://aws.github.io/eks-charts"
}

variable "efa_dra_driver_version" {
  description = "Pinned EFA DRA driver version (dra mode)."
  type        = string
  default     = "v0.3.0"
}

variable "device_class_name" {
  description = "Name of the netdev DRA DeviceClass for EFA NICs (dra mode)."
  type        = string
  default     = "efa-netdev"
}

variable "claim_template_name" {
  description = "Name of the EFA netdev ResourceClaimTemplate (dra mode)."
  type        = string
  default     = "efa-all-nics"
}

variable "dra_namespace" {
  description = "Namespace the EFA ResourceClaimTemplate lives in (workload namespace). The DeviceClass is cluster-scoped."
  type        = string
  default     = "default"
}

variable "ofi_nccl_config" {
  description = "OFI-NCCL plugin env (FI_PROVIDER=efa etc.) surfaced as ConfigMap data for NCCL workloads."
  type        = map(string)
  default = {
    "FI_PROVIDER"            = "efa"
    "FI_EFA_USE_DEVICE_RDMA" = "1"
    "NCCL_PROTO"             = "simple"
  }
  nullable = false
}

variable "gpu_node_selector" {
  description = "Node selector identifying EFA-capable GPU nodes the DaemonSet runs on."
  type        = map(string)
  default     = { "efa.enabled" = "true" }
  nullable    = false
}

variable "helm_timeout" {
  description = "Helm release timeout in seconds."
  type        = number
  default     = 600
}

variable "platform_labels" {
  description = "ADR-0028 Kubernetes-plane labels (dotted keys) on every fabric object."
  type        = map(string)
  default     = {}
  nullable    = false
}
