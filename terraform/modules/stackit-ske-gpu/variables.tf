variable "project_id" {
  description = "STACKIT project UUID"
  type        = string
}

variable "cluster_name" {
  description = "Name of the SKE cluster (max 11 chars in Gardener/SKE constraints)"
  type        = string
}

variable "region" {
  description = "STACKIT region (e.g. eu01, eu02)"
  type        = string
  default     = "eu01"
}

variable "availability_zones" {
  description = "STACKIT availability zones (e.g. [\"eu01-1\", \"eu01-2\"])"
  type        = list(string)
  default     = ["eu01-1", "eu01-2"]
}

variable "kubernetes_version_min" {
  description = "Minimum Kubernetes version for SKE"
  type        = string
  default     = "1.31"
}

variable "network_id" {
  description = "UUID of the STACKIT network for SKE nodes"
  type        = string
}

variable "control_plane_access_scope" {
  description = "Control plane access scope (PUBLIC or PRIVATE)"
  type        = string
  default     = "PUBLIC"
}

variable "auto_upgrade_enabled" {
  description = "Enable automatic Kubernetes patch and machine image updates in maintenance window"
  type        = bool
  default     = true
}

variable "observability_instance_id" {
  description = "Optional STACKIT Observability (Argus) instance ID to link to SKE"
  type        = string
  default     = null
}

variable "system_pool" {
  description = "System CPU node pool configuration"
  type = object({
    name           = optional(string, "system")
    machine_type   = optional(string, "c1.4")
    os_name        = optional(string, "flatcar")
    os_version_min = optional(string, "4081.2.1")
    minimum        = optional(number, 2)
    maximum        = optional(number, 4)
    volume_type    = optional(string, "storage_premium_perf4")
    volume_size    = optional(number, 50)
  })
  default = {}
}

variable "gpu_node_pools" {
  description = "Map of GPU node pool configurations for SKE (L40S, H100, L4)"
  type = map(object({
    machine_type       = string
    os_name            = optional(string, "ubuntu")
    os_version_min     = optional(string, "22.04")
    minimum            = optional(number, 0)
    maximum            = optional(number, 4)
    max_surge          = optional(number, 1)
    availability_zones = optional(list(string))
    volume_type        = optional(string, "storage_premium_perf6")
    volume_size        = optional(number, 200)
    labels             = optional(map(string), {})
    taints = optional(list(object({
      key    = string
      value  = string
      effect = string
    })), [])
  }))
  default = {}
}

variable "labels" {
  description = "Common key-value labels applied to all SKE node pools"
  type        = map(string)
  default     = {}
}
