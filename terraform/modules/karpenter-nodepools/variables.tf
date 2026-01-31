variable "cluster_name" {
  description = "EKS cluster name for subnet/SG discovery tags"
  type        = string
}

variable "node_iam_role_name" {
  description = "IAM role name for Karpenter-provisioned nodes"
  type        = string
}

variable "nodepool_configs" {
  description = "Map of NodePool configurations. Each key becomes a NodePool + EC2NodeClass name."
  type = map(object({
    enabled              = bool
    cpu_limit            = number
    memory_limit         = number
    spot_percentage      = number
    instance_families    = optional(list(string), [])
    architectures        = optional(list(string), ["amd64"])
    consolidation_policy = optional(string, "WhenEmptyOrUnderutilized")
    consolidate_after    = optional(string, "30s")
    weight               = optional(number, 10)
  }))
  default = {}
}
