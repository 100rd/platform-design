# ---------------------------------------------------------------------------------------------------------------------
# IAM Baseline — Catalog Unit
# ---------------------------------------------------------------------------------------------------------------------
# Deploys account-level IAM password policy and MFA enforcement policy.
# This is an org-level resource — deploy once in the management account.
#
# PCI-DSS Requirements:
#   Req 8.2.3 — Password complexity (min length 14)
#   Req 8.2.4 — Password expiry (90 days)
#   Req 8.2.5 — Password history (24 previous passwords)
#   Req 8.3   — MFA enforcement (IAM policy + SSO console config)
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/project/platform-design/terraform/modules/iam-baseline"
}

inputs = {
  name_prefix = ""

  # Password policy — PCI-DSS compliant defaults are in variables.tf
  # Override here only if the live config needs different values.

  tags = {
    Environment = "management"
    ManagedBy   = "terragrunt"
    Compliance  = "pci-dss"
  }
}
