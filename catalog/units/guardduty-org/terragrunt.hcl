# ---------------------------------------------------------------------------------------------------------------------
# GuardDuty Organization — Catalog Unit
# ---------------------------------------------------------------------------------------------------------------------
# Enables GuardDuty across the AWS Organization with all protection features:
#   S3, EKS audit logs, EKS runtime, EBS malware, RDS login, Lambda network.
#
# PCI-DSS Requirements:
#   Req 10.6   — Review logs/security events daily (automated via GuardDuty findings)
#   Req 11.4   — IDS/IPS (GuardDuty is cloud-native intrusion detection)
#   Req 11.5   — Change-detection mechanism (EBS malware scanning)
#
# Required inputs from consuming live config:
#   - delegated_admin_account_id (from organization dependency or account vars)
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/project/platform-design/terraform/modules/guardduty-org"
}

inputs = {
  enable_s3_protection           = true
  enable_eks_audit_log_monitoring = true
  enable_eks_runtime_monitoring  = true
  enable_malware_protection      = true
  enable_rds_protection          = true
  enable_lambda_protection       = true
  auto_enable_org_members        = true

  tags = {
    Environment = "management"
    ManagedBy   = "terragrunt"
    Compliance  = "pci-dss"
  }
}
