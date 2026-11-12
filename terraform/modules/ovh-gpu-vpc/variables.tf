variable "service_name" {
  description = "OVHcloud Public Cloud Project ID (service_name)"
  type        = string
}

variable "network_name" {
  description = "Name of the vRack Private Network"
  type        = string
}

variable "region" {
  description = "OVHcloud Public Cloud compute region (e.g. GRA11 for H100/L40S/L4 GPUs)"
  type        = string
  default     = "GRA11"
}

variable "vlan_id" {
  description = "vRack VLAN ID (1-4000)"
  type        = number
  default     = 140
}

variable "subnet_cidr" {
  description = "Private IPv4 subnet CIDR block"
  type        = string
  default     = "10.215.0.0/16"
}

variable "enable_gateway" {
  description = "Provision an OVHcloud Public Cloud Gateway for outbound SNAT"
  type        = bool
  default     = true
}

variable "gateway_model" {
  description = "OVHcloud Gateway size model (s, m, l)"
  type        = string
  default     = "s"
}
