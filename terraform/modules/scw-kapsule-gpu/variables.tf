variable "project_id" {
  description = "Scaleway project ID"
  type        = string
}

variable "cluster_name" {
  description = "Name of the Scaleway Kapsule cluster"
  type        = string
}

variable "cluster_type" {
  description = "Scaleway Kubernetes cluster commercial tier (kapsule, kapsule-dedicated-4, kapsule-dedicated-8, kapsule-dedicated-16)"
  type        = string
  default     = "kapsule-dedicated-4"

  validation {
    condition     = contains(["kapsule", "kapsule-dedicated-4", "kapsule-dedicated-8", "kapsule-dedicated-16"], var.cluster_type)
    error_message = "cluster_type must be one of: kapsule, kapsule-dedicated-4, kapsule-dedicated-8, kapsule-dedicated-16."
  }
}

variable "kubernetes_version" {
  description = "Kubernetes minor or patch version supported by Scaleway Kapsule"
  type        = string
  default     = "1.32"
}

variable "region" {
  description = "Scaleway region (e.g. fr-par, nl-ams, pl-waw)"
  type        = string
  default     = "fr-par"
}

variable "zone" {
  description = "Default Scaleway availability zone for node pools (e.g. fr-par-2 for H100/L40S)"
  type        = string
  default     = "fr-par-2"
}

variable "private_network_id" {
  description = "ID of the Scaleway VPC Private Network to attach the cluster to"
  type        = string
}

variable "public_ip_disabled" {
  description = "Disable public IPs on worker nodes (routes egress through VPC Public Gateway)"
  type        = bool
  default     = true
}

variable "delete_additional_resources" {
  description = "Delete associated Scaleway Load Balancers and block volumes on cluster destroy"
  type        = bool
  default     = false
}

variable "auto_upgrade_enabled" {
  description = "Enable automatic patch version upgrades during the maintenance window"
  type        = bool
  default     = true
}

variable "scale_down_delay_after_add" {
  description = "How long after scale up that scale down evaluation resumes"
  type        = string
  default     = "5m"
}

variable "scale_down_unneeded_time" {
  description = "How long a GPU node should be unneeded before it is eligible for scale down"
  type        = string
  default     = "5m"
}

variable "system_pool" {
  description = "System CPU node pool configuration"
  type = object({
    node_type              = optional(string, "PRO2-S")
    size                   = optional(number, 2)
    min_size               = optional(number, 2)
    max_size               = optional(number, 4)
    root_volume_type       = optional(string, "sbs_5k")
    root_volume_size_in_gb = optional(number, 50)
  })
  default = {}
}

variable "gpu_node_pools" {
  description = "Map of GPU node pool configurations (L40S, H100, L4)"
  type = map(object({
    node_type              = string
    size                   = optional(number, 1)
    min_size               = optional(number, 0)
    max_size               = optional(number, 4)
    autoscaling            = optional(bool, true)
    autohealing            = optional(bool, true)
    root_volume_type       = optional(string, "sbs_15k")
    root_volume_size_in_gb = optional(number, 200)
    zone                   = optional(string)
    use_placement_group    = optional(bool, true)
    placement_policy_type  = optional(string, "low_latency")
    labels                 = optional(map(string), {})
    taints = optional(list(object({
      key    = string
      value  = string
      effect = string
    })), [])
  }))
  default = {}
}

variable "tags" {
  description = "Common key-value tags applied to cluster and node pools"
  type        = map(string)
  default     = {}
}
