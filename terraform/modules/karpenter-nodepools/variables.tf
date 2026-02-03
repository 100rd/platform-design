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
