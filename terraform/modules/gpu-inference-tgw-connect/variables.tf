variable "name" {
  description = "Name prefix for resources"
  type        = string
}

variable "tgw_connect_attachment_id" {
  description = "TGW Connect attachment ID (from gpu-inference-vpc module)"
  type        = string
}

variable "tgw_route_table_id" {
  description = "TGW route table ID for the prod environment"
  type        = string
  default     = ""
}

variable "shared_route_table_id" {
  description = "TGW shared route table ID for cross-cluster propagation"
  type        = string
  default     = ""
}

variable "pod_cidr" {
  description = "Pod CIDR to route via TGW Connect (100.64.0.0/10)"
  type        = string
  default     = "100.64.0.0/10"
}

variable "enable_static_fallback" {
  description = "Enable static route for Pod CIDR as BGP fallback"
  type        = bool
  default     = true
}

variable "bgp_peers" {
  description = "BGP peer configurations (one per AZ for HA)"
  type = map(object({
    peer_address       = string
    tgw_address        = string
    bgp_asn            = number
    inside_cidr_blocks = list(string)
    availability_zone  = string
  }))
  default = {}
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
