variable "aws_region" {
  description = "AWS region for test resources"
  type        = string
  default     = "us-east-1"
}

variable "test_name" {
  description = "Name of the test for tagging"
  type        = string
  default     = "vpc-integration-test"
}

variable "vpc_name" {
  description = "Name prefix for the VPC"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "azs" {
  description = "Availability zones to use"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "cluster_name" {
  description = "EKS cluster name for Karpenter discovery tags"
  type        = string
  default     = ""
}

variable "enable_ha_nat" {
  description = "Enable HA NAT Gateway"
  type        = bool
  default     = false
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "test"
}

variable "enable_flow_log" {
  description = "Enable VPC flow logs"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
