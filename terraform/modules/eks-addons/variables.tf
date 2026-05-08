variable "cluster_name" {
  description = "EKS cluster name. Used to associate addons with the correct cluster."
  type        = string
  nullable    = false
}

variable "addons" {
  description = <<-EOT
    Map of EKS addons to deploy. Key is the addon name (e.g. "coredns").
    Each object supports the full aws_eks_addon argument surface:
      addon_version            - pin a specific version (null = AWS picks latest compatible version)
      configuration_values     - JSON string of addon configuration overrides
      resolve_conflicts        - behaviour on conflict: OVERWRITE or NONE (default OVERWRITE)
      service_account_role_arn - IRSA role ARN for the addon (optional)
      preserve                 - preserve addon on destroy (default false)
      tags                     - additional tags merged with var.tags
  EOT
  type = map(object({
    addon_version            = optional(string, null)
    configuration_values     = optional(string, null)
    resolve_conflicts        = optional(string, "OVERWRITE")
    service_account_role_arn = optional(string, null)
    preserve                 = optional(bool, false)
    tags                     = optional(map(string), {})
  }))
  default  = {}
  nullable = false
}

variable "tags" {
  description = "Tags applied to all addon resources created by this module."
  type        = map(string)
  default     = {}
}
