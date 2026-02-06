# ---------------------------------------------------------------------------------------------------------------------
# IAM Baseline — Management Account
# ---------------------------------------------------------------------------------------------------------------------
# Enforces PCI-DSS-compliant password policy and provides MFA enforcement policy.
# No dependencies — this can be applied independently of the organization module.
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/project/platform-design/terraform/modules/iam-baseline"
}

inputs = {
  name_prefix = ""

  tags = {
    Environment = "management"
    ManagedBy   = "terragrunt"
    Compliance  = "pci-dss"
  }
}
