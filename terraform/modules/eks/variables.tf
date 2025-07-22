variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version for the cluster"
  type        = string
  default     = "1.33"
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs"
  type        = list(string)
}

variable "ondemand_instance_types" {
  description = "Instance types for on-demand node group"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "ondemand_desired_size" {
  description = "Desired capacity for on-demand node group"
  type        = number
  default     = 2
}

variable "ondemand_min_size" {
  description = "Minimum nodes for on-demand node group"
  type        = number
  default     = 1
}

variable "ondemand_max_size" {
  description = "Maximum nodes for on-demand node group"
  type        = number
  default     = 4
}

variable "spot_instance_types" {
  description = "Instance types for spot node group"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "spot_desired_size" {
  description = "Desired capacity for spot node group"
  type        = number
  default     = 2
}

variable "spot_min_size" {
  description = "Minimum nodes for spot node group"
  type        = number
  default     = 1
}

variable "spot_max_size" {
  description = "Maximum nodes for spot node group"
  type        = number
  default     = 4
}

variable "tags" {
  description = "Tags to apply"
  type        = map(string)
  default     = {}
}
