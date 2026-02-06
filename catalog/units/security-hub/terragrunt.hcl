# ---------------------------------------------------------------------------------------------------------------------
# Security Hub — Catalog Unit
# ---------------------------------------------------------------------------------------------------------------------
# Enables AWS Security Hub with PCI-DSS, CIS, and AWS Foundational standards.
# Aggregates findings from GuardDuty, Config, Inspector, and other services.
#
# PCI-DSS Requirements:
#   Req 6.1    — Identify security vulnerabilities (automated compliance checks)
#   Req 10.6   — Review logs and security events daily (centralized dashboard)
#   Req 11.4   — IDS/IPS findings aggregation
#   Req 12.10  — Incident response (findings trigger response workflows)
#
# No external dependencies required. Should be deployed after GuardDuty and Config
# to aggregate their findings.
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/project/platform-design/terraform/modules/security-hub"
}

inputs = {
  enable_pci_dss_standard          = true
  enable_cis_standard              = true
  enable_aws_foundational_standard = true
  auto_enable_org                  = true
  auto_enable_default_standards    = false

  tags = {
    Environment = "management"
    ManagedBy   = "terragrunt"
    Compliance  = "pci-dss"
  }
}
