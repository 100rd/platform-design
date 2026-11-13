variable "project_id" {
  description = "Scaleway project ID"
  type        = string
}

variable "network_name" {
  description = "Name prefix for the Scaleway VPC, Private Network, and Public Gateway"
  type        = string
}

variable "region" {
  description = "Scaleway region (e.g. fr-par, nl-ams, pl-waw)"
  type        = string
  default     = "fr-par"
}

variable "zone" {
  description = "Scaleway availability zone for the Public Gateway (e.g. fr-par-2)"
  type        = string
  default     = "fr-par-2"
}

variable "subnet_cidr" {
  description = "IPv4 CIDR block for the Private Network IPAM subnet"
  type        = string
  default     = "10.210.0.0/16"
}

variable "enable_public_gateway" {
  description = "Provision a VPC Public Gateway for outbound NAT masquerading on private GPU nodes"
  type        = bool
  default     = true
}

variable "public_gateway_type" {
  description = "Commercial offer type for the Public Gateway (VPC-GW-S, VPC-GW-M, VPC-GW-L)"
  type        = string
  default     = "VPC-GW-S"
}

variable "bastion_enabled" {
  description = "Enable SSH bastion on the Public Gateway"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Key-value tags converted to Scaleway tag strings (key=value)"
  type        = map(string)
  default     = {}
}
