variable "name" {
  description = "Name prefix for RAM share resources"
  type        = string
}

variable "transit_gateway_arn" {
  description = "ARN of the Transit Gateway to share"
  type        = string
}

variable "organization_arn" {
  description = "ARN of the AWS Organization (for org-wide sharing)"
  type        = string
  default     = ""
}

variable "share_with_organization" {
  description = "Whether to share with the entire organization"
  type        = bool
  default     = true
}

variable "share_with_accounts" {
  description = "Map of account name to account ID for targeted sharing (used when share_with_organization = false)"
  type        = map(string)
  default     = {}
}

variable "shared_subnet_arns" {
  description = "List of subnet ARNs to share via RAM (for shared VPC pattern)"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
