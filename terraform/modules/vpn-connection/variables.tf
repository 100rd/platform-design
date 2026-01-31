variable "name" {
  description = "Name prefix for VPN resources"
  type        = string
}

variable "transit_gateway_id" {
  description = "Transit Gateway ID to attach VPN connections to"
  type        = string
}

variable "vpn_connections" {
  description = "Map of VPN connections to create"
  type = map(object({
    remote_ip           = string
    bgp_asn             = number
    static_routes_only  = optional(bool, false)
    static_routes       = optional(list(string), [])
    certificate_arn     = optional(string)
    tunnel1_inside_cidr = optional(string)
    tunnel2_inside_cidr = optional(string)
    tunnel1_psk         = optional(string)
    tunnel2_psk         = optional(string)
  }))
  default = {}
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
