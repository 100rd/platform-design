variable "project_id" {
  description = "STACKIT project UUID"
  type        = string
}

variable "network_name" {
  description = "Name of the STACKIT virtual network"
  type        = string
}

variable "region" {
  description = "STACKIT region (e.g. eu01, eu02)"
  type        = string
  default     = "eu01"
}

variable "routed" {
  description = "Enable dynamic routing and SNAT egress on the STACKIT network"
  type        = bool
  default     = true
}

variable "ipv4_prefix_length" {
  description = "IPv4 subnet prefix length allocated from the STACKIT network area"
  type        = number
  default     = 22
}

variable "ipv4_nameservers" {
  description = "Custom DNS nameservers for the network"
  type        = list(string)
  default     = ["1.1.1.1", "8.8.8.8"]
}

variable "labels" {
  description = "Key-value labels applied to the STACKIT network"
  type        = map(string)
  default     = {}
}
