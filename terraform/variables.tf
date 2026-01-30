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

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid CIDR block."
  }
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "platform-eks"
}

variable "cluster_version" {
  description = "Kubernetes version for EKS cluster"
  type        = string
  default     = "1.32"  # Updated 2026-01-28 from invalid 1.33

  validation {
    condition     = can(regex("^1\\.(2[89]|3[0-2])$", var.cluster_version))
    error_message = "cluster_version must be a supported EKS version (1.28-1.32)."
  }
}

variable "tags" {
  description = "Tags to apply to all resources for cost allocation and organization"
  type        = map(string)
  default = {
    ManagedBy   = "terraform"
    Project     = "platform-design"
    Environment = "dev"
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
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
