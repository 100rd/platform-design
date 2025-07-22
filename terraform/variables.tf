variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "name" {
  description = "Base name for resources"
  type        = string
  default     = "platform"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "platform-eks"
}

variable "cluster_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.33"
}

variable "tags" {
  description = "Tags to apply"
  type        = map(string)
  default     = {}
}

variable "enable_hetzner_nodes" {
  description = "Whether to provision worker nodes on Hetzner"
  type        = bool
  default     = false
}

variable "hetzner_token" {
  description = "API token for Hetzner Cloud"
  type        = string
  default     = ""
  sensitive   = true
}

variable "hetzner_node_count" {
  description = "Number of Hetzner nodes to create"
  type        = number
  default     = 1
}

variable "hetzner_server_type" {
  description = "Hetzner server type"
  type        = string
  default     = "cx31"
}

variable "hetzner_image" {
  description = "Operating system image"
  type        = string
  default     = "ubuntu-22.04"
}

variable "hetzner_location" {
  description = "Hetzner location"
  type        = string
  default     = "fsn1"
}

variable "hetzner_ssh_keys" {
  description = "List of SSH key IDs to add to servers"
  type        = list(string)
  default     = []
}

variable "hetzner_user_data" {
  description = "Optional custom user data for Hetzner nodes"
  type        = string
  default     = ""
}

variable "hetzner_bootstrap_token" {
  description = "kubeadm token for joining nodes"
  type        = string
  default     = ""
  sensitive   = true
}

variable "hetzner_ca_cert_hash" {
  description = "CA cert hash for kubeadm join"
  type        = string
  default     = ""
}
