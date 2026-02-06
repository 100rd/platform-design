variable "identifier" {
  description = "The name of the RDS instance"
  type        = string
  default     = "dns-failover-db"
}

variable "vpc_id" {
  description = "VPC ID where the DB will be created"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs for the DB subnet group"
  type        = list(string)
}

variable "allowed_security_group_ids" {
  description = "List of security group IDs that can access the DB"
  type        = list(string)
  default     = []
}

variable "db_name" {
  description = "The name of the database to create"
  type        = string
  default     = "dns_failover"
}

variable "username" {
  description = "Username for the master DB user"
  type        = string
  default     = "postgres"
}

variable "password" {
  description = "Password for the master DB user"
  type        = string
  sensitive   = true
}

variable "instance_class" {
  description = "The instance type of the RDS instance"
  type        = string
  default     = "db.t3.small"
}

variable "allocated_storage" {
  description = "The allocated storage in gigabytes"
  type        = number
  default     = 20
}

variable "multi_az" {
  description = "Specifies if the RDS instance is multi-AZ"
  type        = bool
  default     = true
}

variable "kms_key_id" {
  description = "ARN of the KMS CMK for RDS storage encryption. When set, storage_encrypted uses this key instead of the default aws/rds key. Required for PCI-DSS Req 3.4."
  type        = string
  default     = null
}

variable "tags" {
  description = "A map of tags to add to all resources"
  type        = map(string)
  default     = {}
}

variable "environment" {
  description = "Environment name (dev, staging, prod). Controls snapshot behavior."
  type        = string
  default     = "dev"
}
