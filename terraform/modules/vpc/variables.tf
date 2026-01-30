variable "name" {
  description = "Name prefix for VPC"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "azs" {
  description = "List of availability zones to use"
  type        = list(string)
  default     = null
}

variable "cluster_name" {
  description = "EKS cluster name for Karpenter discovery tags (optional)"
  type        = string
  default     = ""
}

variable "private_subnet_tags" {
  description = "Additional tags for private subnets"
  type        = map(string)
  default     = {}
}

variable "public_subnet_tags" {
  description = "Additional tags for public subnets"
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

variable "enable_ha_nat" {
  description = "Enable HA NAT Gateway (one per AZ). Set to true for production environments."
  type        = bool
  default     = false
}

variable "environment" {
  description = "Environment name (dev, staging, prod). Affects NAT Gateway configuration."
  type        = string
  default     = "dev"
}
