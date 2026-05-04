# -----------------------------------------------------------------------------
# securityhub-org — Organization-wide AWS Security Hub
# -----------------------------------------------------------------------------
# Closes #164. Thin alias around the existing `security-hub` module which now
# supports delegated administration and cross-region finding aggregation.
#
# Why a wrapper instead of renaming `security-hub`?
#   - Issue #164 asks for `modules/securityhub-org` (mirroring qbiq-ai/infra
#     naming).
#   - The existing `security-hub` module already creates the account
#     enablement, AWS Foundational + CIS + PCI-DSS standard subscriptions,
#     and org auto-enable. Delegated admin and finding aggregator landed in
#     the existing module for #164.
#   - Renaming would force state moves and break BDD compliance tests.
# -----------------------------------------------------------------------------

module "security_hub" {
  source = "../security-hub"

  enable_pci_dss_standard          = var.enable_pci_dss_standard
  enable_cis_standard              = var.enable_cis_standard
  enable_aws_foundational_standard = var.enable_aws_foundational_standard

  auto_enable_org               = var.auto_enable_org
  auto_enable_default_standards = var.auto_enable_default_standards

  # #164 — delegated admin + cross-region aggregation
  delegated_admin_account_id        = var.delegated_admin_account_id
  enable_finding_aggregator         = var.enable_finding_aggregator
  finding_aggregator_linked_regions = var.finding_aggregator_linked_regions

  tags = var.tags
}
