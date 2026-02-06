# ---------------------------------------------------------------------------------------------------------------------
# Security Hub — Management Account
# ---------------------------------------------------------------------------------------------------------------------
# Enables AWS Security Hub with PCI-DSS, CIS, and AWS Foundational standards.
# Should be deployed after GuardDuty and AWS Config so their findings are aggregated.
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/project/platform-design/terraform/modules/security-hub"
}

dependency "guardduty" {
  config_path = "../guardduty-org"

  mock_outputs = {
    detector_id = "mock-detector-id"
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

dependency "config" {
  config_path = "../aws-config"

  mock_outputs = {
    recorder_id = "mock-recorder"
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
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
