# ---------------------------------------------------------------------------------------------------------------------
# IAM Baseline — Catalog Unit
# ---------------------------------------------------------------------------------------------------------------------
# Deploys account-level IAM security controls:
#   - Password policy (PCI-DSS + CIS 1.8-1.14)
#   - MFA enforcement IAM policy for break-glass users
#   - IAM Access Analyzer (CIS 1.20)
#   - S3 account-level public access block (CIS 2.1.5)
#   - EBS encryption by default (CIS 2.2.1)
#
# analyzer_type:
#   ORGANIZATION — deploy in the management account only (requires Organizations trust)
#   ACCOUNT      — deploy in all other accounts (dev, staging, prod, network)
#
# Deploy in every account. Set analyzer_type = "ORGANIZATION" in _org account,
# ACCOUNT everywhere else.
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/project/platform-design/terraform/modules/iam-baseline"
}

locals {
  account_vars     = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  account_name     = local.account_vars.locals.account_name
  org_account_type = try(local.account_vars.locals.org_account_type, "workload")
}

inputs = {
  name_prefix = ""

  # Password policy — PCI-DSS compliant defaults are in variables.tf
  # Override here only if the live config needs different values.

  # CIS 1.20: Use ORGANIZATION in management account, ACCOUNT in workload accounts
  analyzer_type = local.org_account_type == "management" ? "ORGANIZATION" : "ACCOUNT"

  # CIS 2.2.1: Leave empty to use the AWS-managed default EBS key.
  # Set to a KMS key ARN from the kms catalog unit to use a customer-managed key.
  ebs_kms_key_arn = ""

  tags = {
    ManagedBy  = "terragrunt"
    Compliance = "pci-dss,cis"
  }
}
