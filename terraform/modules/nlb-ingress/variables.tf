variable "name" {
  description = "Name prefix for the NLB and associated resources"
  type        = string
}

variable "enabled" {
  description = "Whether to create the NLB resources"
  type        = bool
  default     = true
}

variable "vpc_id" {
  description = "VPC ID where the NLB target group is created"
  type        = string
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs for NLB placement"
  type        = list(string)
}

variable "certificate_arn" {
  description = "ACM certificate ARN for TLS termination on the 443 listener"
  type        = string
  default     = ""
}

variable "ssl_policy" {
  description = "SSL policy for the TLS listener"
  type        = string
  default     = "ELBSecurityPolicy-TLS13-1-2-2021-06"
}

variable "health_check_path" {
  description = "HTTP path for target group health checks"
  type        = string
  default     = "/healthz"
}

variable "health_check_port" {
  description = "Port for target group health checks"
  type        = string
  default     = "traffic-port"
}

variable "health_check_protocol" {
  description = "Protocol for target group health checks (TCP or HTTP)"
  type        = string
  default     = "TCP"
}

variable "deregistration_delay" {
  description = "Seconds to wait before deregistering a draining target"
  type        = number
  default     = 30
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
