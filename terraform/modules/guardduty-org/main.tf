# ---------------------------------------------------------------------------------------------------------------------
# GuardDuty Organization Detector
# ---------------------------------------------------------------------------------------------------------------------
# Enables GuardDuty at the organization level with all protection features:
#   - S3 data event protection
#   - EKS audit log monitoring
#   - EKS runtime monitoring (security agent)
#   - EBS malware protection
#   - RDS login activity monitoring
#   - Lambda network activity monitoring
#
# PCI-DSS Requirements addressed:
#   Req 10.6   — Review logs and security events daily (automated via GuardDuty)
#   Req 11.4   — IDS/IPS — GuardDuty serves as a cloud-native intrusion detection system
#   Req 11.5   — Change-detection mechanism for critical files (EBS malware scanning)
# ---------------------------------------------------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

locals {
  admin_account_id = var.delegated_admin_account_id != "" ? var.delegated_admin_account_id : data.aws_caller_identity.current.account_id
}

# ---------------------------------------------------------------------------------------------------------------------
# GuardDuty Detector
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_guardduty_detector" "this" {
  enable = true

  # Send findings at 15-minute intervals (most frequent)
  finding_publishing_frequency = "FIFTEEN_MINUTES"

  datasources {
    s3_logs {
      enable = var.enable_s3_protection
    }

    kubernetes {
      audit_logs {
        enable = var.enable_eks_audit_log_monitoring
      }
    }

    malware_protection {
      scan_ec2_instance_with_findings {
        ebs_volumes {
          enable = var.enable_malware_protection
        }
      }
    }
  }

  tags = merge(var.tags, {
    Name          = "guardduty-org-detector"
    pci-dss-scope = "true"
    Compliance    = "pci-dss-req-10.6,11.4"
  })
}

# ---------------------------------------------------------------------------------------------------------------------
# GuardDuty Organization Configuration
# ---------------------------------------------------------------------------------------------------------------------
# Auto-enable GuardDuty for all current and future member accounts.
# Ensures no account in the organization is left unmonitored.
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_guardduty_organization_configuration" "this" {
  detector_id = aws_guardduty_detector.this.id

  auto_enable_organization_members = var.auto_enable_org_members ? "ALL" : "NONE"

  datasources {
    s3_logs {
      auto_enable = var.enable_s3_protection
    }

    kubernetes {
      audit_logs {
        enable = var.enable_eks_audit_log_monitoring
      }
    }

    malware_protection {
      scan_ec2_instance_with_findings {
        ebs_volumes {
          auto_enable = var.enable_malware_protection
        }
      }
    }
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# EKS Runtime Monitoring Feature
# ---------------------------------------------------------------------------------------------------------------------
# Deploys a GuardDuty security agent to EKS clusters for runtime threat detection.
# This is configured separately from the detector datasources.
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_guardduty_detector_feature" "eks_runtime" {
  detector_id = aws_guardduty_detector.this.id
  name        = "EKS_RUNTIME_MONITORING"
  status      = var.enable_eks_runtime_monitoring ? "ENABLED" : "DISABLED"

  additional_configuration {
    name   = "EKS_ADDON_MANAGEMENT"
    status = var.enable_eks_runtime_monitoring ? "ENABLED" : "DISABLED"
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# RDS Login Activity Monitoring
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_guardduty_detector_feature" "rds_login" {
  detector_id = aws_guardduty_detector.this.id
  name        = "RDS_LOGIN_EVENTS"
  status      = var.enable_rds_protection ? "ENABLED" : "DISABLED"
}

# ---------------------------------------------------------------------------------------------------------------------
# Lambda Network Activity Monitoring
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_guardduty_detector_feature" "lambda" {
  detector_id = aws_guardduty_detector.this.id
  name        = "LAMBDA_NETWORK_LOGS"
  status      = var.enable_lambda_protection ? "ENABLED" : "DISABLED"
}

# ---------------------------------------------------------------------------------------------------------------------
# Delegated Administrator
# ---------------------------------------------------------------------------------------------------------------------
# Delegates GuardDuty administration to a specified account (typically a security account).
# Only created if the delegated admin is a different account than the current one.
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_guardduty_organization_admin_account" "this" {
  count = local.admin_account_id != data.aws_caller_identity.current.account_id ? 1 : 0

  admin_account_id = local.admin_account_id
}
