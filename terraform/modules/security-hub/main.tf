# ---------------------------------------------------------------------------------------------------------------------
# AWS Security Hub
# ---------------------------------------------------------------------------------------------------------------------
# Enables Security Hub as a centralized security findings aggregator.
# Subscribes to PCI-DSS, CIS, and AWS Foundational standards for automated compliance checks.
# Integrates findings from GuardDuty, Config, Inspector, and third-party tools.
#
# PCI-DSS Requirements addressed:
#   Req 6.1    — Establish process for identifying security vulnerabilities (automated findings)
#   Req 10.6   — Review logs and security events daily (centralized dashboard)
#   Req 11.4   — IDS/IPS — aggregates GuardDuty IDS findings
#   Req 12.10  — Incident response plan (findings trigger response workflows)
# ---------------------------------------------------------------------------------------------------------------------

data "aws_region" "current" {}

# ---------------------------------------------------------------------------------------------------------------------
# Security Hub Account
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_securityhub_account" "this" {
  auto_enable_controls    = true
  enable_default_standards = var.auto_enable_default_standards

  control_finding_generator = "SECURITY_CONTROL"
}

# ---------------------------------------------------------------------------------------------------------------------
# PCI-DSS v3.2.1 Standard
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_securityhub_standards_subscription" "pci_dss" {
  count = var.enable_pci_dss_standard ? 1 : 0

  standards_arn = "arn:aws:securityhub:${data.aws_region.current.name}::standards/pci-dss/v/3.2.1"

  depends_on = [aws_securityhub_account.this]
}

# ---------------------------------------------------------------------------------------------------------------------
# CIS AWS Foundations Benchmark v1.4.0
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_securityhub_standards_subscription" "cis" {
  count = var.enable_cis_standard ? 1 : 0

  standards_arn = "arn:aws:securityhub:${data.aws_region.current.name}::standards/cis-aws-foundations-benchmark/v/1.4.0"

  depends_on = [aws_securityhub_account.this]
}

# ---------------------------------------------------------------------------------------------------------------------
# AWS Foundational Security Best Practices
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_securityhub_standards_subscription" "aws_foundational" {
  count = var.enable_aws_foundational_standard ? 1 : 0

  standards_arn = "arn:aws:securityhub:${data.aws_region.current.name}::standards/aws-foundational-security-best-practices/v/1.0.0"

  depends_on = [aws_securityhub_account.this]
}

# ---------------------------------------------------------------------------------------------------------------------
# Organization Configuration
# ---------------------------------------------------------------------------------------------------------------------
# Auto-enable Security Hub for new member accounts joining the organization.
# This ensures no account is left without centralized security monitoring.
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_securityhub_organization_configuration" "this" {
  auto_enable           = var.auto_enable_org
  auto_enable_standards = var.auto_enable_default_standards ? "DEFAULT" : "NONE"

  depends_on = [aws_securityhub_account.this]
}
