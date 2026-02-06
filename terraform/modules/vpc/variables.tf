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

# ---------------------------------------------------------------------------------------------------------------------
# VPC Flow Logs — PCI-DSS Req 10 (logging & monitoring)
# ---------------------------------------------------------------------------------------------------------------------

variable "enable_flow_log" {
  description = "Enable VPC Flow Logs. Required for PCI-DSS compliance."
  type        = bool
  default     = true
}

variable "flow_log_destination_type" {
  description = "Type of flow log destination. One of: cloud-watch-logs, s3, kinesis-data-firehose."
  type        = string
  default     = "cloud-watch-logs"
}

variable "create_flow_log_cloudwatch_log_group" {
  description = "Whether to create a CloudWatch log group for VPC flow logs."
  type        = bool
  default     = true
}

variable "flow_log_cloudwatch_log_group_retention_in_days" {
  description = "Number of days to retain flow logs in CloudWatch. PCI-DSS Req 10.7 mandates 365 days minimum."
  type        = number
  default     = 365
}

variable "flow_log_max_aggregation_interval" {
  description = "Maximum interval of time (seconds) during which a flow of packets is captured. Valid values: 60, 600."
  type        = number
  default     = 60
}

variable "flow_log_traffic_type" {
  description = "Type of traffic to capture. Valid values: ACCEPT, REJECT, ALL."
  type        = string
  default     = "ALL"
}
