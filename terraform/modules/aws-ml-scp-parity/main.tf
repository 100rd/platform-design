# ---------------------------------------------------------------------------------------------------------------------
# aws-ml-scp-parity — SCP deny-list plane for the greenfield AWS GPU/ML OU
# ---------------------------------------------------------------------------------------------------------------------
# ADR-0044 (greenfield AWS EKS GPU ML foundation, A1) + ADR-0048 (AWS-native ML
# backends: S3 + RDS + ABAC). This module is the AWS analog of the GCP org-policy
# deny-list plane defined in ADR-0040 D1 — it adds GPU/ML-OU-scoped Service Control
# Policies that the broad org-wide `terraform/modules/scps` does not cover, so the
# net-new ML estate inherits the same preventive guardrails as the rest of the org.
#
# APPLY-GATED / DEFAULT-OFF: every SCP + attachment is created via `count` gated on
# `var.enabled` (master, default false) AND a per-policy toggle. With defaults,
# `terraform plan` produces ZERO resources — nothing is ever created at plan/validate
# time. SCPs are organization-wide and high-blast-radius; enabling requires an explicit
# human apply + blast-radius review (project rule: critical-decisions / terraform).
#
# Blast-radius bound: attachments target `var.ml_target_ou_ids` (the GPU/ML OU) ONLY,
# never the org root — the broad root-level SCPs (S3 public, EBS-encryption) already
# live in `terraform/modules/scps`. This module narrows further for the ML estate.
#
# ADR-0028: every policy carries `var.tags` (platform:system=security /
# component=scp-parity / owner=team-sec). `aws_organizations_policy` IS taggable.
# ---------------------------------------------------------------------------------------------------------------------

locals {
  # A policy is materialised only when the master gate AND its own toggle are on.
  create_imdsv2  = var.enabled && var.require_imdsv2
  create_ebs_enc = var.enabled && var.require_ebs_encryption
  create_no_keys = var.enabled && var.deny_long_lived_access_keys
  create_region  = var.enabled && var.restrict_gpu_regions
  name_prefix    = "${var.project}-ml"
  has_target     = length(var.ml_target_ou_ids) > 0
}

# ---------------------------------------------------------------------------------------------------------------------
# SCP 1 — Require IMDSv2 on EC2 RunInstances (deny metadata-v1 GPU nodes)
# AWS analog of GPU-node SSRF hardening; SOC2 CC6.1 (logical access).
# ---------------------------------------------------------------------------------------------------------------------
resource "aws_organizations_policy" "require_imdsv2" {
  count = local.create_imdsv2 ? 1 : 0

  name        = "${local.name_prefix}-RequireIMDSv2"
  description = "ML OU: deny EC2 RunInstances unless IMDSv2 (HttpTokens=required) — protects GPU node credentials from SSRF"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "DenyImdsV1"
        Effect   = "Deny"
        Action   = "ec2:RunInstances"
        Resource = "arn:aws:ec2:*:*:instance/*"
        Condition = {
          StringNotEquals = {
            "ec2:MetadataHttpTokens" = "required"
          }
        }
      },
    ]
  })

  tags = var.tags
}

# ---------------------------------------------------------------------------------------------------------------------
# SCP 2 — Require EBS encryption (deny unencrypted volumes on GPU nodes)
# AWS analog of GCP gcp.restrictNonCmekServices (ADR-0040 D1); SOC2 CC6.1 (encryption).
# ---------------------------------------------------------------------------------------------------------------------
resource "aws_organizations_policy" "require_ebs_encryption" {
  count = local.create_ebs_enc ? 1 : 0

  name        = "${local.name_prefix}-RequireEbsEncryption"
  description = "ML OU: deny creation of unencrypted EBS volumes — GPU node disks must be KMS-encrypted at rest"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "DenyUnencryptedEbs"
        Effect   = "Deny"
        Action   = "ec2:CreateVolume"
        Resource = "*"
        Condition = {
          Bool = {
            "ec2:Encrypted" = "false"
          }
        }
      },
    ]
  })

  tags = var.tags
}

# ---------------------------------------------------------------------------------------------------------------------
# SCP 3 — Deny long-lived IAM access keys (force Pod Identity / role assumption)
# AWS analog of GCP iam.disableServiceAccountKeyCreation (ADR-0040 D1/D2); the forcing
# function for keyless identity (ADR-0018). SOC2 CC6.1/CC6.3.
# ---------------------------------------------------------------------------------------------------------------------
resource "aws_organizations_policy" "deny_access_keys" {
  count = local.create_no_keys ? 1 : 0

  name        = "${local.name_prefix}-DenyLongLivedAccessKeys"
  description = "ML OU: deny iam:CreateAccessKey — workloads must use EKS Pod Identity / STS, never static keys (ADR-0018)"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "DenyCreateAccessKey"
        Effect   = "Deny"
        Action   = "iam:CreateAccessKey"
        Resource = "*"
      },
    ]
  })

  tags = var.tags
}

# ---------------------------------------------------------------------------------------------------------------------
# SCP 4 — Restrict GPU/ML resources to allowed regions (data residency)
# AWS analog of GCP gcp.resourceLocations (ADR-0040 D1); SOC2 C1.1. The Terraform
# execution role is exempt so it can reach global services (IAM/STS/Route53).
# ---------------------------------------------------------------------------------------------------------------------
resource "aws_organizations_policy" "restrict_regions" {
  count = local.create_region ? 1 : 0

  name        = "${local.name_prefix}-RestrictGpuRegions"
  description = "ML OU: deny resource creation outside allowed GPU regions; Terraform role exempt for global services"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyOutsideAllowedRegions"
        Effect = "Deny"
        NotAction = [
          "iam:*",
          "sts:*",
          "route53:*",
          "cloudfront:*",
          "organizations:*",
          "support:*",
          "budgets:*",
          "ce:*",
        ]
        Resource = "*"
        Condition = {
          StringNotEquals = {
            "aws:RequestedRegion" = var.allowed_gpu_regions
          }
          # Exempt the Terraform execution role from the region restriction.
          ArnNotLike = {
            "aws:PrincipalArn" = "arn:aws:iam::*:role/${var.terraform_role_name_pattern}"
          }
        }
      },
    ]
  })

  tags = var.tags
}

# ---------------------------------------------------------------------------------------------------------------------
# Attachments — each SCP attaches to every ML target OU (gated by the same toggles).
# No attachment is created when there is no target OU or the gate is off.
# ---------------------------------------------------------------------------------------------------------------------
resource "aws_organizations_policy_attachment" "require_imdsv2" {
  for_each = local.create_imdsv2 && local.has_target ? toset(var.ml_target_ou_ids) : toset([])

  policy_id = aws_organizations_policy.require_imdsv2[0].id
  target_id = each.value
}

resource "aws_organizations_policy_attachment" "require_ebs_encryption" {
  for_each = local.create_ebs_enc && local.has_target ? toset(var.ml_target_ou_ids) : toset([])

  policy_id = aws_organizations_policy.require_ebs_encryption[0].id
  target_id = each.value
}

resource "aws_organizations_policy_attachment" "deny_access_keys" {
  for_each = local.create_no_keys && local.has_target ? toset(var.ml_target_ou_ids) : toset([])

  policy_id = aws_organizations_policy.deny_access_keys[0].id
  target_id = each.value
}

resource "aws_organizations_policy_attachment" "restrict_regions" {
  for_each = local.create_region && local.has_target ? toset(var.ml_target_ou_ids) : toset([])

  policy_id = aws_organizations_policy.restrict_regions[0].id
  target_id = each.value
}
