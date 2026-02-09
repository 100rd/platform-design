variable "cilium_version" {
  description = "Cilium Helm chart version"
  type        = string
  default     = "1.16.5"
}

variable "cluster_endpoint" {
  description = "EKS cluster API server endpoint (without https://)"
  type        = string
}

variable "replace_kube_proxy" {
  description = "Replace kube-proxy with Cilium eBPF. Set to false initially for safer migration."
  type        = bool
  default     = false
}

variable "enable_hubble" {
  description = "Enable Hubble for network observability"
  type        = bool
  default     = true
}

variable "enable_hubble_ui" {
  description = "Enable Hubble UI dashboard"
  type        = bool
  default     = true
}

variable "enable_service_monitor" {
  description = "Enable Prometheus ServiceMonitor for Cilium/Hubble metrics"
  type        = bool
  default     = true
}

variable "enable_prefix_delegation" {
  description = "Enable prefix delegation for higher pod density per node"
  type        = bool
  default     = true
}

variable "enable_bandwidth_manager" {
  description = "Enable bandwidth manager for network QoS"
  type        = bool
  default     = true
}

variable "enable_default_deny" {
  description = "Deploy a default-deny CiliumClusterwideNetworkPolicy"
  type        = bool
  default     = false
}

variable "enable_encryption" {
  description = "Enable transparent encryption for pod-to-pod traffic (PCI-DSS Req 4.1)"
  type        = bool
  default     = true
}

variable "encryption_type" {
  description = "Encryption type: wireguard or ipsec"
  type        = string
  default     = "wireguard"

  validation {
    condition     = contains(["wireguard", "ipsec"], var.encryption_type)
    error_message = "encryption_type must be either 'wireguard' or 'ipsec'."
  }
}

variable "operator_replicas" {
  description = "Number of Cilium operator replicas"
  type        = number
  default     = 2
}

variable "extra_config" {
  description = "Extra Cilium configuration to merge"
  type        = map(any)
  default     = {}
}

variable "module_depends_on" {
  description = "List of resources this module depends on"
  type        = list(any)
  default     = []
}

variable "enable_clustermesh" {
  description = "Enable Cilium ClusterMesh for multi-cluster service discovery"
  type        = bool
  default     = false
}

variable "cluster_mesh_name" {
  description = "Unique cluster name for ClusterMesh (e.g., staging-euw1)"
  type        = string
  default     = ""
}

variable "cluster_mesh_id" {
  description = "Unique cluster ID for ClusterMesh (1-255, must be unique per mesh)"
  type        = number
  default     = 0

  validation {
    condition     = var.cluster_mesh_id >= 0 && var.cluster_mesh_id <= 255
    error_message = "cluster_mesh_id must be between 0 and 255."
  }
}

variable "clustermesh_apiserver_replicas" {
  description = "Number of ClusterMesh API server replicas"
  type        = number
  default     = 2
}
