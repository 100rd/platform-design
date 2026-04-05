variable "project" {
  description = "Project name used in resource naming (e.g. 'platform-design')"
  type        = string
}

variable "environment" {
  description = "Environment name used in resource naming and alarm dimensions (e.g. 'dev', 'prod')"
  type        = string
}

variable "alert_email" {
  description = "Email address for SNS alarm notifications. This triggers an SNS subscription confirmation email."
  type        = string
}

variable "kms_key_arn" {
  description = "KMS key ARN for SNS topic encryption. Leave empty to skip SNS encryption."
  type        = string
  default     = ""
}

variable "enable_billing_alarm" {
  description = "Whether to create the billing alarm. Only valid in the management account with us-east-1 as the deployment region (billing metrics are global, us-east-1 only)."
  type        = bool
  default     = false
}

variable "billing_threshold_usd" {
  description = "Estimated charges threshold in USD for the billing alarm"
  type        = number
  default     = 500
}

variable "cpu_threshold_percent" {
  description = "CPU utilization percentage threshold for the EC2 alarm"
  type        = number
  default     = 80
}

variable "memory_threshold_percent" {
  description = "Memory utilization percentage threshold for the EC2 alarm (requires CloudWatch agent on instances)"
  type        = number
  default     = 85
}

variable "alb_arn_suffix" {
  description = "ALB ARN suffix for ALB-specific alarms (e.g. 'app/my-alb/1234567890abcdef'). Leave empty to skip ALB alarms."
  type        = string
  default     = ""
}

variable "alb_5xx_threshold" {
  description = "ALB HTTP 5xx count threshold per 5-minute period"
  type        = number
  default     = 50
}

variable "state_bucket_region" {
  description = "AWS region of the Terraform state S3 bucket, used to construct the bucket name dimension for the state size alarm"
  type        = string
  default     = "eu-west-1"
}

variable "tags" {
  description = "Tags to apply to all resources in this module"
  type        = map(string)
  default     = {}
}
