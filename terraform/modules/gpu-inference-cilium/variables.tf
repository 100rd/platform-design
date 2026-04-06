variable "cilium_version" {
  description = "Cilium Helm chart version"
  type        = string
  default     = "1.19.2"
}

variable "cluster_endpoint" {
  description = "EKS cluster API endpoint (without https://)"
  type        = string
}

variable "pod_cidr" {
  description = "Pod CIDR block announced via BGP"
  type        = string
  default     = "100.64.0.0/10"
}

variable "pod_cidr_mask_size" {
  description = "Per-node Pod CIDR mask size"
  type        = string
  default     = "24"
}

variable "operator_replicas" {
  description = "Number of Cilium operator replicas"
  type        = number
  default     = 2
}

variable "bpf_lb_map_max" {
  description = "Maximum BPF LB map entries"
  type        = string
  default     = "512000"
}

variable "bpf_policy_map_max" {
  description = "Maximum BPF policy map entries"
  type        = string
  default     = "65536"
}

variable "enable_bgp_peering" {
  description = "Enable BGP peering policy for TGW Connect"
  type        = bool
  default     = false
}

variable "bgp_local_asn" {
  description = "Local ASN for BGP peering"
  type        = number
  default     = 65100
}

variable "bgp_peers" {
  description = "BGP peer configurations for TGW Connect"
  type = list(object({
    address = string
    asn     = number
  }))
  default = []
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
