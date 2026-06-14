variable "enabled" {
  description = "Deploy the DRANET DeviceClass + ResourceClaimTemplate. Set false to no-op (e.g. clusters without managed DRANET / RoCE pools)."
  type        = bool
  default     = true
  nullable    = false
}

variable "device_class_name" {
  description = "Name of the RoCE netdev DeviceClass."
  type        = string
  default     = "roce-netdev"
}

variable "claim_template_name" {
  description = "Name of the ResourceClaimTemplate binding RDMA NICs to a pod."
  type        = string
  default     = "rdma-all-nics"
}

variable "namespace" {
  description = "Namespace for the ResourceClaimTemplate (where RoCE-consuming pods run)."
  type        = string
  default     = "gpu-inference"
}

variable "dranet_driver" {
  description = "DRA driver name the DeviceClass selects on. GKE managed DRANET / open-source dranet uses dra.net."
  type        = string
  default     = "dra.net"
}

variable "platform_labels" {
  description = "Additional ADR-0028 Kubernetes-plane platform labels (dotted keys) merged onto the DRA objects."
  type        = map(string)
  default     = {}
}
