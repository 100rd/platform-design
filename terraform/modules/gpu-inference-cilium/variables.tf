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

# -------------------------------------------------------
# Socket-level load balancing
# -------------------------------------------------------

variable "enable_sockops" {
  description = "Enable socket-level load balancing. Intercepts connect() syscall and rewrites directly to backend IP -- zero per-packet DNAT overhead for east-west traffic."
  type        = bool
  default     = true
}

# -------------------------------------------------------
# Maglev consistent hashing
# -------------------------------------------------------

variable "maglev_hash_seed" {
  description = "Consistent hash seed for Maglev LB table. Must be identical on all nodes. Change only during a planned maintenance window."
  type        = string
  default     = "JLfvgnHc2kaSUFaI"
}

# -------------------------------------------------------
# XDP + Direct Server Return
# -------------------------------------------------------

variable "enable_xdp" {
  description = "Enable XDP native acceleration for north-south LB. Requires ENA NIC (satisfied by AWS) and kernel 5.10+ (Bottlerocket satisfies this)."
  type        = bool
  default     = true
}

variable "xdp_devices" {
  description = "Network interfaces for XDP attachment. AWS ENA presents as eth0 on Bottlerocket."
  type        = list(string)
  default     = ["eth0"]
}

variable "enable_dsr" {
  description = "Enable Direct Server Return -- return traffic goes directly from pod to client, bypassing NLB. Requires NLB in IP target mode."
  type        = bool
  default     = true
}

variable "dsr_dispatch" {
  description = "DSR dispatch method. 'opt' uses IP options (same-subnet). 'geneve' works cross-subnet. For AWS same-AZ, 'opt' is preferred."
  type        = string
  default     = "opt"

  validation {
    condition     = contains(["opt", "geneve", "ipip"], var.dsr_dispatch)
    error_message = "dsr_dispatch must be 'opt', 'geneve', or 'ipip'."
  }
}

# -------------------------------------------------------
# Hubble L7 observability
# -------------------------------------------------------

variable "enable_hubble_ui" {
  description = "Enable Hubble UI. Disable in prod to reduce attack surface; access via hubble relay CLI."
  type        = bool
  default     = false
}

variable "hubble_relay_replicas" {
  description = "Number of Hubble Relay replicas for HA"
  type        = number
  default     = 2
}

# -------------------------------------------------------
# ClusterMesh
# -------------------------------------------------------

variable "enable_clustermesh" {
  description = "Enable Cilium ClusterMesh for multi-cluster service discovery"
  type        = bool
  default     = false
}

variable "cluster_mesh_name" {
  description = "Unique cluster name for ClusterMesh. Use format: {env}-{region}-{role} e.g. prod-euw1-gpu"
  type        = string
  default     = "prod-euw1-gpu"
}

variable "cluster_mesh_id" {
  description = "Unique cluster ID for ClusterMesh (1-255, unique per mesh). Platform=1, blockchain=2, gpu-analysis=3, gpu-inference=4."
  type        = number
  default     = 4

  validation {
    condition     = var.cluster_mesh_id >= 1 && var.cluster_mesh_id <= 255
    error_message = "cluster_mesh_id must be between 1 and 255."
  }
}

variable "clustermesh_apiserver_replicas" {
  description = "Number of ClusterMesh API server replicas"
  type        = number
  default     = 3
}

variable "enable_clustermesh_global_services" {
  description = "Create ClusterMesh global service annotations for shared platform services (VictoriaMetrics, etc.)"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
