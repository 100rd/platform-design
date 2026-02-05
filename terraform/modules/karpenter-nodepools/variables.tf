variable "cluster_name" {
  description = "EKS cluster name for subnet/SG discovery tags"
  type        = string
}

variable "node_iam_role_name" {
  description = "IAM role name for Karpenter-provisioned nodes"
  type        = string
}

variable "ami_family" {
  description = "AMI family for nodes. Use 'Bottlerocket' for Cilium CNI, 'AL2023' for VPC CNI."
  type        = string
  default     = "Bottlerocket"

  validation {
    condition     = contains(["AL2023", "Bottlerocket", "AL2", "Custom"], var.ami_family)
    error_message = "ami_family must be one of: AL2023, Bottlerocket, AL2, Custom"
  }
}

variable "nodepool_configs" {
  description = "Map of NodePool configurations. Each key becomes a NodePool + EC2NodeClass name."
  type = map(object({
    enabled                 = bool
    cpu_limit               = number
    memory_limit            = number
    spot_percentage         = number
    instance_families       = optional(list(string), [])
    instance_sizes          = optional(list(string), [])
    excluded_instance_types = optional(list(string), [])
    architectures           = optional(list(string), ["amd64"])
    consolidation_policy    = optional(string, "WhenEmptyOrUnderutilized")
    consolidate_after       = optional(string, "30s")
    weight                  = optional(number, 10)
    root_volume_size        = optional(string, "50Gi")
    labels                  = optional(map(string), {})
    taints = optional(list(object({
      key    = string
      value  = string
      effect = string
    })), [])
    startup_taints = optional(list(object({
      key    = string
      value  = string
      effect = string
    })), [])
    # --- HPC / Placement Group fields (optional, backward compatible) ---
    placement_group_name = optional(string)      # EC2NodeClass spec.placement.placementGroupName
    availability_zone    = optional(string)       # EC2NodeClass spec.placement.availabilityZone (single-AZ pinning)
    block_device_overrides = optional(object({    # Custom EBS for HPC (io2, high IOPS)
      volume_type = optional(string, "gp3")
      volume_size = optional(string)              # Overrides root_volume_size
      iops        = optional(number, 3000)
      throughput  = optional(number, 125)          # Ignored for io2
      encrypted   = optional(bool, true)
    }))

    expire_after = optional(string, "720h")
    disruption_budgets = optional(list(object({
      nodes    = optional(string)
      schedule = optional(string)
      duration = optional(string)
    })))
  }))
  default = {}
}

variable "additional_node_tags" {
  description = "Additional tags to apply to all Karpenter-provisioned nodes"
  type        = map(string)
  default     = {}
}
