variable "enabled" {
  description = "Create the Cloud Armor security policy. Set false to no-op (gated rollout)."
  type        = bool
  default     = true
  nullable    = false
}

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "security_policy_name" {
  description = "Name of the Cloud Armor security policy."
  type        = string
}

variable "enable_adaptive_protection" {
  description = "Enable Adaptive Protection (ML-based L7 DDoS defense)."
  type        = bool
  default     = true
  nullable    = false
}

variable "rate_limit_threshold" {
  description = "Allowed requests per client per rate_limit_interval_sec before banning."
  type        = number
  default     = 600
}

variable "rate_limit_interval_sec" {
  description = "Sliding window (seconds) for the rate-limit threshold."
  type        = number
  default     = 60
}

variable "rate_limit_ban_duration_sec" {
  description = "How long (seconds) a client is banned after exceeding the threshold."
  type        = number
  default     = 300
}

variable "waf_preconfigured_rules" {
  description = "Cloud Armor preconfigured WAF expression names to deny on, e.g. [\"sqli-v33-stable\", \"xss-v33-stable\"]. Empty disables WAF rules."
  type        = list(string)
  default     = ["sqli-v33-stable", "xss-v33-stable"]
}

variable "labels" {
  description = "ADR-0028 platform labels. Cloud Armor policies do not support resource labels; platform.system is surfaced in the policy description for attribution."
  type        = map(string)
  default     = {}
}
