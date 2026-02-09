variable "enabled" {
  description = "Whether to create the TGW peering attachment"
  type        = bool
  default     = true
}

variable "name" {
  description = "Name prefix for resources"
  type        = string
}

variable "local_tgw_id" {
  description = "Transit Gateway ID in the local region"
  type        = string
}

variable "peer_tgw_id" {
  description = "Transit Gateway ID in the peer region"
  type        = string
}

variable "peer_region" {
  description = "AWS region of the peer Transit Gateway"
  type        = string
}

variable "peer_account_id" {
  description = "AWS account ID owning the peer Transit Gateway"
  type        = string
}

variable "local_route_table_ids" {
  description = "Map of name to TGW route table ID in the local region where peer CIDRs should be routed"
  type        = map(string)
  default     = {}
}

variable "peer_cidrs" {
  description = "List of CIDR blocks reachable via the peer Transit Gateway"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
