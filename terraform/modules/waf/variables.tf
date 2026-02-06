variable "name" {
  description = "Name of the WAF WebACL"
  type        = string
}

variable "description" {
  description = "Description of the WebACL"
  type        = string
  default     = "WAF WebACL for ALB ingress protection"
}

variable "rate_limit" {
  description = "Rate limit per IP per 5-minute window"
  type        = number
  default     = 2000
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days (PCI-DSS Req 10.7: minimum 365)"
  type        = number
  default     = 365
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
