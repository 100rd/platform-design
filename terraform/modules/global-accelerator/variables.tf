variable "name" {
  description = "Name for the Global Accelerator and associated resources"
  type        = string
}

variable "enabled" {
  description = "Whether to create the Global Accelerator resources"
  type        = bool
  default     = true
}

variable "ip_address_type" {
  description = "IP address type for the accelerator (IPV4 or DUAL_STACK)"
  type        = string
  default     = "IPV4"

  validation {
    condition     = contains(["IPV4", "DUAL_STACK"], var.ip_address_type)
    error_message = "ip_address_type must be IPV4 or DUAL_STACK."
  }
}

variable "flow_logs_enabled" {
  description = "Whether to enable flow logs for the accelerator"
  type        = bool
  default     = true
}

variable "flow_logs_s3_bucket" {
  description = "S3 bucket name for flow log delivery"
  type        = string
}

variable "flow_logs_s3_prefix" {
  description = "S3 key prefix for flow log objects"
  type        = string
  default     = "global-accelerator/"
}

variable "listeners" {
  description = "List of listener configurations for the accelerator"
  type = list(object({
    port_ranges = list(object({
      from = number
      to   = number
    }))
    protocol        = string
    client_affinity = string
  }))
}

variable "endpoint_groups" {
  description = "Map of region key to endpoint group configuration"
  type = map(object({
    endpoint_id             = string
    weight                  = number
    health_check_port       = number
    health_check_protocol   = string
    health_check_path       = string
    health_check_interval   = number
    threshold_count         = number
    traffic_dial_percentage = number
  }))
  default = {}
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
