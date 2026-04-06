# ---------------------------------------------------------------------------------------------------------------------
# GPU Inference VPC — Variables
# ---------------------------------------------------------------------------------------------------------------------

variable "name" {
  description = "Name prefix for all resources"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "azs" {
  description = "List of availability zones"
  type        = list(string)
}

variable "private_subnets" {
  description = "List of private subnet CIDR blocks"
  type        = list(string)
}

variable "intra_subnets" {
  description = "List of intra subnet CIDR blocks (GPU node-to-node, no NAT route)"
  type        = list(string)
}

variable "cluster_name" {
  description = "Name of the EKS cluster for subnet tagging"
  type        = string
}

variable "pod_cidr" {
  description = "Pod CIDR block announced via BGP (not part of VPC CIDR)"
  type        = string
  default     = "100.64.0.0/10"
}

variable "single_nat_gateway" {
  description = "Use a single NAT gateway (true) or one per AZ (false)"
  type        = bool
  default     = false
}

variable "transit_gateway_id" {
  description = "Transit Gateway ID for TGW Connect attachment"
  type        = string
  default     = ""
}

variable "tgw_route_table_id" {
  description = "Transit Gateway route table ID for association and propagation"
  type        = string
  default     = ""
}

variable "tgw_destination_cidr" {
  description = "Destination CIDR for TGW routes in VPC route tables"
  type        = string
  default     = "10.0.0.0/8"
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
