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
