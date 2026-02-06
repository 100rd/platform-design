variable "name" {
  description = "Name used for the distribution comment and OAC identifier"
  type        = string
}

variable "s3_bucket_id" {
  description = "ID of the S3 bucket used as the CloudFront origin"
  type        = string
}

variable "s3_bucket_arn" {
  description = "ARN of the S3 bucket used for the bucket policy"
  type        = string
}

variable "s3_bucket_regional_domain_name" {
  description = "Regional domain name of the S3 bucket for the CloudFront origin"
  type        = string
}

variable "price_class" {
  description = "CloudFront price class (PriceClass_100 = EU/NA, PriceClass_200 = EU/NA/Asia, PriceClass_All = all edge locations)"
  type        = string
  default     = "PriceClass_100"

  validation {
    condition     = contains(["PriceClass_100", "PriceClass_200", "PriceClass_All"], var.price_class)
    error_message = "price_class must be PriceClass_100, PriceClass_200, or PriceClass_All."
  }
}

variable "allowed_countries" {
  description = "ISO 3166-1 alpha-2 country codes for geo-restriction whitelist. Empty list disables geo-restriction."
  type        = list(string)
  default     = ["FR", "DE", "GB", "ES", "IT", "NL", "BE", "AT", "CH", "PT"]
}

variable "default_ttl" {
  description = "Default TTL in seconds for cached objects"
  type        = number
  default     = 86400
}

variable "max_ttl" {
  description = "Maximum TTL in seconds for cached objects"
  type        = number
  default     = 31536000
}

variable "web_acl_id" {
  description = "ARN of a WAF WebACL to associate with the distribution (optional)"
  type        = string
  default     = null
}

variable "aliases" {
  description = "Custom domain names (CNAMEs) for the distribution"
  type        = list(string)
  default     = []
}

variable "acm_certificate_arn" {
  description = "ARN of the ACM certificate for custom domain HTTPS. Required when aliases is non-empty."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
