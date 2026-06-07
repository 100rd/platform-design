# ---------------------------------------------------------------------------------------------------------------------
# Resource Control Policies (RCPs)
# ---------------------------------------------------------------------------------------------------------------------
# Provenance: ADR-0017 (resource-side data perimeter and declarative org controls).
#
# RCPs are the RESOURCE-side half of the AWS data perimeter, symmetric to the
# principal-side SCP (`DataPerimeter-DenyExternalPrincipals` in modules/scps).
# Where an SCP gates *callers* (an identity inside the org cannot reach out of
# the org), an RCP gates *our resources* — it denies any principal OUTSIDE the
# org from acting on S3 / STS / KMS / SecretsManager / SQS resources owned by
# accounts the RCP is attached to. This closes the gap an SCP cannot: a public
# bucket, an over-broad KMS grant, or a cross-account trust no longer punches
# through the perimeter.
#
# RCPs have their OWN slot budget (separate from the 5/5 SCP cap per target),
# so this control does not consume SCP slots — see ADR-0017 Context.
#
# EVALUATION MODEL (new mental model for reviewers, ADR-0017 Consequences):
#   RCPs evaluate AFTER identity-based, SCP, and resource-based policy. An
#   explicit Deny here is final. The seed RCP below is an *org-perimeter* deny
#   with an AWS-service carve-out — mis-scoping it could deny legitimate
#   cross-service / log-delivery access, which is exactly why this module was
#   STAGED in the Policy-Staging OU first (ADR-0017 Implementation notes step 3)
#   and only promoted to root once staging was verified clean (step 4).
#
# CARVE-OUTS (mirrors the principal-side SCP exemption philosophy):
#   - aws:PrincipalIsAWSService = true  — first-party AWS service principals
#     (log delivery, Config recorder, CloudTrail, cross-service calls) keep
#     working; their service-linked roles often lack a full PrincipalOrgID.
#   The deny uses *IfExists semantics so calls that lack a fully-resolved
#   PrincipalOrgID context (rare service/STS edge cases) do not false-trip.
# ---------------------------------------------------------------------------------------------------------------------

# Org-perimeter RCP — deny resource access from any principal outside our org.
# Covers the canonical RCP-supported services (ADR-0017): S3, STS, KMS,
# SecretsManager, SQS.
resource "aws_organizations_policy" "org_perimeter" {
  name        = "RCP-DataPerimeter-DenyExternalAccess"
  description = "Resource-side data perimeter: deny S3/STS/KMS/SecretsManager/SQS access from principals outside the org (AWS service principals exempt). ADR-0017."
  type        = "RESOURCE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyExternalAccessToResources"
        Effect = "Deny"
        Principal = {
          AWS = "*"
        }
        Action = [
          "s3:*",
          "sts:*",
          "kms:*",
          "secretsmanager:*",
          "sqs:*",
        ]
        Resource = "*"
        Condition = {
          StringNotEqualsIfExists = {
            "aws:PrincipalOrgID" = var.organization_id
          }
          BoolIfExists = {
            "aws:PrincipalIsAWSService" = "false"
          }
        }
      }
    ]
  })

  tags = var.tags
}

# ---------------------------------------------------------------------------------------------------------------------
# Policy Attachment
# ---------------------------------------------------------------------------------------------------------------------
# GRADUATION — staged rollout → root promotion (ADR-0017 Implementation notes):
#   step 3 (done)  — attached to the Policy-Staging OU first, verified no
#                    legitimate access breaks (a small test-account set).
#   step 4 (now)   — promoted to root, post-soak. The terragrunt unit
#                    `_org/_global/rcps` now passes BOTH the Policy-Staging OU id
#                    and the organization root id in `target_ou_ids`.
#
# This module is parameterized by `target_ou_ids` (a for_each set). Because the
# attachment iterates the targets, adding the root id is ADDITIVE — the
# Policy-Staging attachment is retained alongside the new root attachment, and
# the org-perimeter policy resource itself is unchanged.
#
# ROLLBACK: remove the root id from `target_ou_ids` (in the terragrunt unit) and
# re-plan/apply. Terraform destroys only the root attachment instance; the
# policy and the Policy-Staging attachment survive, reverting cleanly to
# staged-only. Emptying `target_ou_ids` detaches everywhere while leaving the
# policy defined-but-unattached (the lowest-risk full disable).
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_organizations_policy_attachment" "org_perimeter" {
  for_each = toset(var.target_ou_ids)

  policy_id = aws_organizations_policy.org_perimeter.id
  target_id = each.value
}
