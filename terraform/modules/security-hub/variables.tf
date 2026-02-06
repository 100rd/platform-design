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
# Common
# ---------------------------------------------------------------------------------------------------------------------

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
