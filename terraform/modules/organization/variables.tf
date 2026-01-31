variable "organization_name" {
  description = "Name of the organization (for tagging)"
  type        = string
}

variable "member_accounts" {
  description = "Map of member accounts to create"
  type = map(object({
    account_id = string
    email      = string
    ou         = string
  }))
  default = {}
}

variable "organizational_units" {
  description = "Map of OUs to create. parent = 'Root' for top-level, or the name of a top-level OU for nesting."
  type = map(object({
    parent = string
  }))
  default = {}
}

variable "enabled_policy_types" {
  description = "List of policy types to enable"
  type        = list(string)
  default     = ["SERVICE_CONTROL_POLICY"]
}

variable "aws_service_access_principals" {
  description = "AWS service principals to enable for organization-wide integration"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
