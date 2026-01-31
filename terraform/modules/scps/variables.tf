variable "organization_id" {
  description = "AWS Organization ID"
  type        = string
}

variable "ou_ids" {
  description = "Map of OU name to OU ID for policy attachment"
  type        = map(string)
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
