variable "service_name" {
  description = "OVHcloud Public Cloud Project ID (service_name)"
  type        = string
}

variable "cluster_name" {
  description = "Name of the OVHcloud MKS cluster"
  type        = string
}

variable "region" {
  description = "OVHcloud region (e.g. GRA11 for H100/L40S/L4 GPU flavors)"
  type        = string
  default     = "GRA11"
}

variable "kubernetes_version" {
  description = "Kubernetes minor version supported by OVHcloud MKS"
  type        = string
  default     = "1.31"
}

variable "cluster_plan" {
  description = "OVHcloud MKS plan (free or standard — standard enables Cilium eBPF CNI & HA)"
  type        = string
  default     = "standard"
}

variable "private_network_id" {
  description = "OpenStack UUID of the vRack Private Network"
  type        = string
}

variable "nodes_subnet_id" {
  description = "Subnet ID inside the vRack Private Network for MKS worker nodes"
  type        = string
}

variable "default_vrack_gateway" {
  description = "Default gateway IP in the private subnet (or empty when managed by OVH Gateway)"
  type        = string
  default     = ""
}

variable "update_policy" {
  description = "MKS auto-upgrade policy (ALWAYS_UPDATE, MINIMAL_DOWNTIME, NEVER_UPDATE)"
  type        = string
  default     = "MINIMAL_DOWNTIME"
}

variable "system_pool" {
  description = "System CPU node pool configuration"
  type = object({
    flavor_name   = optional(string, "b3-16")
    desired_nodes = optional(number, 2)
    min_nodes     = optional(number, 2)
    max_nodes     = optional(number, 4)
  })
  default = {}
}

variable "gpu_node_pools" {
  description = "Map of GPU node pool configurations for OVHcloud MKS (l40s-90, h100-380, l4-90)"
  type = map(object({
    flavor_name   = string
    desired_nodes = optional(number, 1)
    min_nodes     = optional(number, 0)
    max_nodes     = optional(number, 4)
    autoscale     = optional(bool, true)
    anti_affinity = optional(bool, false)
    labels        = optional(map(string), {})
    taints = optional(list(object({
      key    = string
      value  = string
      effect = string
    })), [])
  }))
  default = {}
}

variable "labels" {
  description = "Common key-value labels applied to all MKS node pools"
  type        = map(string)
  default     = {}
}
