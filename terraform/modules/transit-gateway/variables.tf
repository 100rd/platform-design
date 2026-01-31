variable "name" {
  description = "Name prefix for Transit Gateway resources"
  type        = string
}

variable "amazon_side_asn" {
  description = "ASN for the Amazon side of the TGW BGP session"
  type        = number
  default     = 64512
}

variable "enable_multicast" {
  description = "Enable multicast support on the TGW"
  type        = bool
  default     = false
}

variable "route_tables" {
  description = "Map of route table names to create (e.g., prod, nonprod, shared, inspection)"
  type        = map(object({}))
  default = {
    prod       = {}
    nonprod    = {}
    shared     = {}
  }
}

variable "blackhole_cidrs" {
  description = "Map of route-table-name to CIDR to blackhole (for isolation)"
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
