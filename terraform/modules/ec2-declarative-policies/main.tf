# ---------------------------------------------------------------------------------------------------------------------
# EC2 Declarative Policies
# ---------------------------------------------------------------------------------------------------------------------
# Provenance: ADR-0017 (resource-side data perimeter and declarative org controls), Decision item 2.
#
# An AWS Organizations DECLARATIVE_POLICY_EC2 expresses *desired state* for the EC2
# control plane and is enforced at the API layer across the org — replacing brittle
# deny-SCP + Config-rule pairs. This module enforces, per ADR-0017:
#   - IMDSv2 required (http_tokens = required)         -> retires the require_imdsv2 SCP
#   - block public EBS snapshot sharing
#   - block public AMI sharing
#   - allowed-AMI providers (audit-first, then enforce)
#
# Declarative policies use the `@@assign` inheritance operator (NOT IAM policy language).
#
# STAGED ROLLOUT (mirrors modules/rcps, ADR-0017 Implementation notes steps 3–4):
#   step 3 — attach to the Policy-Staging OU first (allowed-AMI in `audit_mode`) so a
#            mis-scoped setting is caught in a limited blast radius.
#   step 4 — promote to root post-soak by appending the org root id to target_ou_ids
#            (additive for_each), and flip allowed_images_state audit_mode -> enabled.
# ROLLBACK: empty target_ou_ids to detach everywhere (policy stays defined-but-unattached).
# ---------------------------------------------------------------------------------------------------------------------

locals {
  ec2_attributes = merge(
    {
      exception_message = { "@@assign" = var.exception_message }
    },
    var.require_imdsv2 ? {
      instance_metadata_defaults = {
        http_tokens                 = { "@@assign" = "required" }
        http_put_response_hop_limit = { "@@assign" = tostring(var.imds_hop_limit) }
        http_endpoint               = { "@@assign" = "no_preference" }
        instance_metadata_tags      = { "@@assign" = "no_preference" }
      }
    } : {},
    var.block_public_ebs_snapshots ? {
      snapshot_block_public_access = { state = { "@@assign" = "block_new_sharing" } }
    } : {},
    var.block_public_amis ? {
      image_block_public_access = { state = { "@@assign" = "block_new_sharing" } }
    } : {},
    var.enable_allowed_images ? {
      allowed_images_settings = {
        state = { "@@assign" = var.allowed_images_state }
        image_criteria = {
          criteria_1 = {
            allowed_image_providers = { "@@assign" = var.allowed_image_providers }
          }
        }
      }
    } : {},
  )
}

resource "aws_organizations_policy" "ec2" {
  name        = "DeclarativeEC2-Baseline"
  description = "EC2 declarative baseline: IMDSv2 required, block public EBS-snapshot/AMI sharing, allowed-AMI providers. ADR-0017."
  # DECLARATIVE_POLICY_EC2 is a valid AWS Organizations policy type; the tflint AWS
  # ruleset enum lags behind AWS and flags it as invalid. Suppress that stale check.
  # tflint-ignore: aws_organizations_policy_invalid_type
  type = "DECLARATIVE_POLICY_EC2"

  content = jsonencode({
    ec2_attributes = local.ec2_attributes
  })

  tags = var.tags
}

# ---------------------------------------------------------------------------------------------------------------------
# Policy Attachment — staged rollout → root promotion (for_each = additive/reversible).
# ---------------------------------------------------------------------------------------------------------------------
resource "aws_organizations_policy_attachment" "ec2" {
  for_each = toset(var.target_ou_ids)

  policy_id = aws_organizations_policy.ec2.id
  target_id = each.value
}
