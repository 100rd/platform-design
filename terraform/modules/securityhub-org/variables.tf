# Pass-through inputs to terraform/modules/security-hub.

variable "enable_pci_dss_standard" {
  description = "Enable PCI-DSS v3.2.1 standard."
  type        = bool
  default     = true
}

variable "enable_cis_standard" {
  description = "Enable CIS AWS Foundations Benchmark v1.4.0."
  type        = bool
  default     = true
}

variable "enable_aws_foundational_standard" {
  description = "Enable AWS Foundational Security Best Practices."
  type        = bool
  default     = true
}

variable "auto_enable_org" {
  description = "Auto-enable Security Hub for new org member accounts."
  type        = bool
  default     = true
}

variable "auto_enable_default_standards" {
  description = "Auto-enable default standards for new member accounts."
  type        = bool
  default     = false
}

# #164 — delegated admin + cross-region aggregation

variable "delegated_admin_account_id" {
  description = "Account to delegate Security Hub admin to (typically security account). Empty / equal-to-caller -> no delegation."
  type        = string
  default     = ""
}

variable "enable_finding_aggregator" {
  description = "Create a finding aggregator (cross-region aggregation). Run only in the admin account."
  type        = bool
  default     = false
}

variable "finding_aggregator_linked_regions" {
  description = "Specific regions to aggregate findings from. Empty -> ALL_REGIONS."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags applied to taggable resources."
  type        = map(string)
  default     = {}
}
