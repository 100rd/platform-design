variable "name_prefix" {
  description = "Prefix for Hetzner server names"
  type        = string
}

variable "node_count" {
  description = "Number of nodes to create"
  type        = number
  default     = 1
}

variable "server_type" {
  description = "Hetzner server type"
  type        = string
  default     = "cx31"
}

variable "image" {
  description = "OS image to use"
  type        = string
  default     = "ubuntu-22.04"
}

variable "location" {
  description = "Hetzner location"
  type        = string
  default     = "fsn1"
}

variable "ssh_keys" {
  description = "SSH key IDs allowed to access the server"
  type        = list(string)
  default     = []
}

variable "user_data" {
  description = "Cloud-init user data for node bootstrap"
  type        = string
  default     = ""
}

variable "labels" {
  description = "Labels to apply to servers"
  type        = map(string)
  default     = {}
}
