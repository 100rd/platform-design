variable "vpc_id" {
  description = "ID of the VPC in which to create the endpoints"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs for Interface endpoint ENIs. Use private subnets."
  type        = list(string)
  default     = []
}

variable "security_group_ids" {
  description = "List of security group IDs to attach to Interface endpoints. Must allow HTTPS (443) inbound from the VPC CIDR."
  type        = list(string)
  default     = []
}

variable "route_table_ids" {
  description = "List of route table IDs for Gateway endpoint route associations (S3 and DynamoDB)"
  type        = list(string)
  default     = []
}

variable "name_prefix" {
  description = "Prefix for endpoint Name tags (e.g. 'platform-design-dev-' produces 'platform-design-dev-s3')"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags to apply to all VPC endpoint resources"
  type        = map(string)
  default     = {}
}
