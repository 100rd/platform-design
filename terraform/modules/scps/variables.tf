variable "project" {
  description = "Project name used in resource naming and SCP policy names (e.g. 'platform-design')"
  type        = string
  default     = "platform-design"
}

variable "organization_id" {
  description = "AWS Organization ID"
  type        = string
}

variable "ou_ids" {
  description = "Map of OU name to OU ID for policy attachment. Include 'Root' key with root ID for root-level attachments via ou_ids. Use root_ids for root-level SCPs."
  type        = map(string)
}

variable "workload_ou_names" {
  description = "List of OU names that are considered workload OUs. The deny-root SCP is attached to these only (excludes management/infrastructure)."
  type        = list(string)
  default     = ["NonProd", "Prod"]
}

variable "allowed_regions" {
  description = "List of AWS regions where resources can be created. Used in the region-restriction SCP."
  type        = list(string)
  default = [
    "eu-west-1",
    "eu-west-2",
    "eu-west-3",
    "eu-central-1",
    "us-east-1",
  ]
}

variable "root_ids" {
  description = "List of Organization root IDs for root-level SCP attachments (deny_s3_public, require_ebs_encryption). Attaching at root avoids the 5-SCP-per-OU limit since these apply globally."
  type        = list(string)
  default     = []
}

variable "suspended_ou_id" {
  description = "ID of the Suspended/Quarantine OU. The deny-all SCP is attached here to quarantine compromised accounts. Leave empty to skip (the Suspended OU must exist first)."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags to apply to SCP resources"
  type        = map(string)
  default     = {}
}
