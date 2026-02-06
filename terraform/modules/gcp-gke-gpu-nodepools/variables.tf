variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "cluster_id" {
  description = "GKE cluster ID (projects/PROJECT/locations/LOCATION/clusters/NAME)"
  type        = string
}

variable "cluster_name" {
  description = "GKE cluster name"
  type        = string
}

variable "zone" {
  description = "GCP zone for GPU node pools (single-zone for locality)"
  type        = string
}

variable "node_pool_configs" {
  description = "Map of node pool configurations"
  type = map(object({
    machine_type       = string
    accelerator_type   = optional(string)
    accelerator_count  = optional(number, 0)
    disk_size_gb       = optional(number, 100)
    disk_type          = optional(string, "pd-ssd")
    spot               = optional(bool, false)
    min_node_count     = optional(number, 0)
    max_node_count     = optional(number, 3)
    initial_node_count = optional(number, 0)
    labels             = optional(map(string), {})
    taints = optional(list(object({
      key    = string
      value  = string
      effect = string
    })), [])
  }))
}

variable "labels" {
  description = "Common labels to apply to all node pools"
  type        = map(string)
  default     = {}
}
