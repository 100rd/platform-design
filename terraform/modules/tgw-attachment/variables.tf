variable "enabled" {
  description = "Whether to create the TGW attachment"
  type        = bool
  default     = true
}

variable "name" {
  description = "Name prefix for resources"
  type        = string
}

variable "transit_gateway_id" {
  description = "Transit Gateway ID (shared via RAM from network account)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID to attach"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for the TGW attachment (one per AZ, typically private subnets)"
  type        = list(string)
}

variable "route_table_id" {
  description = "TGW route table ID to associate with (prod, nonprod, or shared)"
  type        = string
  default     = ""
}

variable "vpc_route_table_ids" {
  description = "Map of name to VPC route table ID where TGW routes should be added"
  type        = map(string)
  default     = {}
}

variable "tgw_destination_cidr" {
  description = "Destination CIDR for TGW routes in VPC (e.g., 10.0.0.0/8 for all internal)"
  type        = string
  default     = "10.0.0.0/8"
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
