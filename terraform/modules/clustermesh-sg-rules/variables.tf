variable "enabled" {
  description = "Whether to create the ClusterMesh security group rules"
  type        = bool
  default     = true
}

variable "node_security_group_id" {
  description = "EKS node security group ID where ClusterMesh rules will be added"
  type        = string
}

variable "peer_vpc_cidrs" {
  description = "Map of region name to VPC CIDR for peer clusters (e.g., { eu-central-1 = \"10.13.0.0/16\" })"
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
