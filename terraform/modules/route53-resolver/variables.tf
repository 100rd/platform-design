variable "name" {
  description = "Name prefix for resolver resources"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where resolver endpoints are created"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for resolver endpoints (one per AZ, minimum 2)"
  type        = list(string)
}

variable "enable_inbound" {
  description = "Create inbound resolver endpoint (on-prem → AWS)"
  type        = bool
  default     = true
}

variable "enable_outbound" {
  description = "Create outbound resolver endpoint (AWS → on-prem/partner)"
  type        = bool
  default     = true
}

variable "allowed_cidrs" {
  description = "CIDR blocks allowed to query the resolver endpoints"
  type        = list(string)
  default     = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
}

variable "forwarding_rules" {
  description = "Map of DNS forwarding rules for outbound resolution"
  type = map(object({
    domain     = string
    target_ips = list(object({
      ip   = string
      port = optional(number, 53)
    }))
  }))
  default = {}
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
