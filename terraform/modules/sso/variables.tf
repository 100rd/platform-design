variable "organization_id" {
  description = "AWS Organization ID"
  type        = string
}

variable "member_accounts" {
  description = "Map of member accounts"
  type = map(object({
    account_id = string
    email      = string
    ou         = string
  }))
  default = {}
}

variable "permission_sets" {
  description = "Map of permission sets to create"
  type = map(object({
    description      = string
    session_duration = string
    managed_policies = list(string)
  }))
  default = {}
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
