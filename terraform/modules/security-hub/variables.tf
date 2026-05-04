# ---------------------------------------------------------------------------------------------------------------------
# Security Hub Module Variables
# ---------------------------------------------------------------------------------------------------------------------

variable "enable_pci_dss_standard" {
  description = "Enable PCI-DSS v3.2.1 compliance standard in Security Hub"
  type        = bool
  default     = true
}

variable "enable_cis_standard" {
  description = "Enable CIS AWS Foundations Benchmark v1.4.0 in Security Hub"
  type        = bool
  default     = true
}

variable "enable_aws_foundational_standard" {
  description = "Enable AWS Foundational Security Best Practices standard"
  type        = bool
  default     = true
}

variable "auto_enable_org" {
  description = "Automatically enable Security Hub for new organization member accounts"
  type        = bool
  default     = true
}

variable "auto_enable_default_standards" {
  description = "Automatically enable default security standards for new member accounts"
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------------------------------------------------
# Delegated administrator + cross-region aggregation (#164)
# ---------------------------------------------------------------------------------------------------------------------

variable "delegated_admin_account_id" {
  description = "AWS account ID to delegate Security Hub administration to (typically the security account). When set and != caller, creates aws_securityhub_organization_admin_account. Closes the #164 'delegated admin = security account' criterion."
  type        = string
  default     = ""
}

variable "enable_finding_aggregator" {
  description = "Create aws_securityhub_finding_aggregator to aggregate findings across regions to the home region. Should be set in the SecurityHub admin account only. Closes the #164 'aggregation across regions' criterion."
  type        = bool
  default     = false
}

variable "finding_aggregator_linked_regions" {
  description = "List of regions to aggregate findings from. Empty list means ALL_REGIONS (default behaviour). Set explicit regions if you want to opt-in only certain ones."
  type        = list(string)
  default     = []
}

# ---------------------------------------------------------------------------------------------------------------------
# Common
# ---------------------------------------------------------------------------------------------------------------------

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
