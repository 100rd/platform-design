variable "placement_groups" {
  description = "Map of placement groups to create. Key is used as a logical identifier."
  type = map(object({
    name            = string
    strategy        = string           # "cluster" | "spread" | "partition"
    partition_count = optional(number)  # Only for partition strategy (1-7)
    spread_level    = optional(string)  # Only for spread strategy: "host" | "rack"
  }))

  validation {
    condition = alltrue([
      for k, v in var.placement_groups : contains(["cluster", "spread", "partition"], v.strategy)
    ])
    error_message = "strategy must be one of: cluster, spread, partition"
  }
}

variable "tags" {
  description = "Tags to apply to all placement groups"
  type        = map(string)
  default     = {}
}
