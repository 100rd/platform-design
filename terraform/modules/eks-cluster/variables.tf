variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "dns-failover-cluster"
}

variable "cluster_version" {
  description = "Kubernetes version to use for the EKS cluster"
  type        = string
  default     = "1.29"
}

variable "vpc_id" {
  description = "ID of the VPC where the cluster will be deployed"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs for the cluster"
  type        = list(string)
}

variable "instance_types" {
  description = "List of instance types for the node groups"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "min_size" {
  description = "Minimum number of nodes in the node group"
  type        = number
  default     = 3
}

variable "max_size" {
  description = "Maximum number of nodes in the node group"
  type        = number
  default     = 5
}

variable "desired_size" {
  description = "Desired number of nodes in the node group"
  type        = number
  default     = 3
}

variable "tags" {
  description = "A map of tags to add to all resources"
  type        = map(string)
  default     = {}
}
