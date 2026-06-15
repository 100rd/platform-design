# ---------------------------------------------------------------------------------------------------------------------
# aws-eks-gpu-nodepools — Karpenter GPU pools (spot / scale-to-zero / consolidation / EFA) (ADR-0046 D1/D3, ADR-0045 D1/D2)
# ---------------------------------------------------------------------------------------------------------------------

variable "enabled" {
  description = "Master toggle. When false the module creates no NodePools (default-OFF; apply-gated)."
  type        = bool
  default     = false
  nullable    = false
}

variable "cluster_name" {
  description = "EKS cluster name (from aws-eks-gpu) for Karpenter subnet/SG discovery."
  type        = string
}

variable "node_iam_role_name" {
  description = "IAM role name for Karpenter-provisioned GPU nodes."
  type        = string
  default     = ""
}

variable "ami_family" {
  description = "AMI family for GPU nodes. Bottlerocket (ADR-0030 default) bakes the NVIDIA driver/toolkit."
  type        = string
  default     = "Bottlerocket"

  validation {
    condition     = contains(["AL2023", "Bottlerocket", "AL2", "Custom"], var.ami_family)
    error_message = "ami_family must be one of: AL2023, Bottlerocket, AL2, Custom."
  }
}

variable "gpu_pools" {
  description = <<-EOT
    Map of GPU Karpenter pool name => config. Serving pools default spot-first +
    scale-to-zero + consolidation (ADR-0046 D1/D3); EFA training pools set spot_percentage = 0
    and enable_efa = true with a cluster placement group + single-AZ pin (ADR-0045 D1/D2).
    EFA under Karpenter uses the EFA *device plugin* (mode derived by aws-eks-efa-fabric), never DRA.
  EOT
  type = map(object({
    instance_families    = optional(list(string), ["g6", "g5"])
    instance_sizes       = optional(list(string), [])
    spot_percentage      = optional(number, 100)
    consolidation_policy = optional(string, "WhenEmptyOrUnderutilized")
    consolidate_after    = optional(string, "30s")
    cpu_limit            = optional(number, 1000)
    memory_limit         = optional(number, 4000)
    weight               = optional(number, 10)
    enable_efa           = optional(bool, false)
    placement_group_name = optional(string)
    availability_zone    = optional(string)
    extra_labels         = optional(map(string), {})
  }))
  default = {
    # Cheap elastic serving pool: spot-first, scale-to-zero, consolidating.
    serving = {
      instance_families = ["g6", "g5"]
      spot_percentage   = 100
      enable_efa        = false
    }
    # EFA-capable bursty training pool: on-demand (no spot mid-NCCL), placement-group + single-AZ.
    training-efa = {
      instance_families = ["p5", "p4d"]
      spot_percentage   = 0
      enable_efa        = true
    }
  }
  nullable = false
}

variable "additional_node_tags" {
  description = "ADR-0028 platform:* tags applied to all Karpenter-provisioned GPU nodes."
  type        = map(string)
  default     = {}
  nullable    = false
}
