package terraform.platform_tags_ml

import rego.v1

# ---------------------------------------------------------------------------
# Policy: ADR-0028 taxonomy + ABAC coverage for the NET-NEW AWS ML estate
#
# WS-E (AWS ML platform plan, §7 decision #13 / §3 coverage caveat). The existing
# tests/opa/platform_tags.rego enforces the platform taxonomy on *existing* AWS
# resource types but has NO rules for the net-new `aws-eks-gpu-*` / `aws-ml-*` /
# `aws-eks-efa-fabric` / `aws-eks-inference-gateway` estate introduced by ADRs
# 0044–0048 — so taxonomy enforcement on those modules was NOT automatic. This file
# closes that gap WITHOUT editing platform_tags.rego (kept separate so the two
# policies evolve independently and the WS-E PR stays file-disjoint).
#
# Two enforcement layers:
#
#   1. TAGGED-TYPE FLOOR — the net-new ML resource types listed in
#      `_ml_taggable_types` MUST carry the three required platform tags
#      (platform:system / platform:component / platform:owner), non-empty. Unlike the
#      generic policy's exempt-list approach, these types are an explicit ALLOW-LIST:
#      a net-new ML resource that ships without the taxonomy fails the plan, and it
#      cannot be silently dropped by adding it to an exempt set.
#
#   2. ABAC FLOOR — IAM policy documents created for the ML estate
#      (`aws_iam_policy` whose taxonomy marks it part of an `ml-*` system) that grant
#      access to S3 / KMS / Secrets MUST carry the ADR-0028 ABAC tag-match condition
#      `aws:ResourceTag/platform:system == ${aws:PrincipalTag/platform:system}`, so a
#      least-privilege grant is also ownership-scoped (the `aws-ml-abac-iam` contract).
#
# Evaluated by Conftest against the Terraform plan JSON, same harness as the other
# tests/opa/*.rego (see .github/workflows/conftest-opa.yml). Plan/validate-only —
# this is a policy gate, it applies nothing.
# ---------------------------------------------------------------------------

_required_platform_tags := {"platform:system", "platform:component", "platform:owner"}

# Net-new ML/GPU resource types that MUST carry the platform taxonomy. This is the
# explicit allow-list that closes the coverage gap: terraform-engineer supplies the
# per-module resource-type list, WS-E (security) curates it here.
#
# Covers the resource types the ADR-0044–0048 modules emit:
#   - aws-eks-gpu / aws-eks-gpu-vpc / aws-eks-gpu-operator / -dcgm / -scheduling
#   - aws-eks-gpu-nodepools / -managed-nodegroup / aws-eks-efa-fabric
#   - aws-ml-artifact-store (S3) / aws-ml-abac-iam (IAM) / aws-ml-scp-parity (SCP)
#   - aws-eks-inference-gateway (serving front, ADR-0047)
_ml_taggable_types := {
  # EKS cluster + GPU compute
  "aws_eks_cluster",
  "aws_eks_node_group",
  "aws_eks_addon",
  "aws_launch_template",
  "aws_autoscaling_group",
  # GPU VPC + EFA fabric
  "aws_vpc",
  "aws_subnet",
  "aws_security_group",
  "aws_placement_group",
  # ML artifact store + encryption
  "aws_s3_bucket",
  "aws_kms_key",
  "aws_db_instance",
  # ML identity / policy
  "aws_iam_role",
  "aws_iam_policy",
  "aws_eks_pod_identity_association",
  "aws_organizations_policy",
  # Serving front (inference gateway, ADR-0047) + WAF wiring
  "aws_wafv2_web_acl",
  "aws_lb",
  "aws_lb_target_group",
}

# A resource is "ML estate" when its taxonomy marks it part of an ml-* / gpu-* /
# security system OR it is one of the SCP/IAM types this WS introduces. We key off
# the platform:system tag value so the rule does not over-reach into the existing
# (already-covered) estate.
_ml_system_prefixes := {"ml-", "gpu-"}
_ml_system_exact := {"ml-platform", "ml-pipeline", "ml-monitoring", "security"}

_is_managed(actions) if {
  some a in actions
  a in {"create", "update"}
}

_tags_of(rc) := object.get(rc.change.after, "tags", {})

_is_ml_estate(rc) if {
  tags := _tags_of(rc)
  sys := object.get(tags, "platform:system", "")
  sys in _ml_system_exact
}

_is_ml_estate(rc) if {
  tags := _tags_of(rc)
  sys := object.get(tags, "platform:system", "")
  some p in _ml_system_prefixes
  startswith(sys, p)
}

# ---------------------------------------------------------------------------
# Layer 1 — TAGGED-TYPE FLOOR: net-new ML resource types must carry every required tag
# ---------------------------------------------------------------------------
deny contains msg if {
  some addr, rc in input.resource_changes
  rc.type in _ml_taggable_types
  _is_managed(rc.change.actions)
  tags := _tags_of(rc)
  some required_tag in _required_platform_tags
  not tags[required_tag]
  msg := sprintf(
    "POLICY VIOLATION [platform-tags-ml]: net-new ML resource %q (type: %s) is missing required platform tag %q — ADR-0028 taxonomy is mandatory on the aws-eks-gpu-* / aws-ml-* estate (WS-E gap closure, plan §7 #13)",
    [addr, rc.type, required_tag],
  )
}

# Empty values are also a violation (mirrors the generic policy).
deny contains msg if {
  some addr, rc in input.resource_changes
  rc.type in _ml_taggable_types
  _is_managed(rc.change.actions)
  tags := _tags_of(rc)
  some required_tag in _required_platform_tags
  tags[required_tag] == ""
  msg := sprintf(
    "POLICY VIOLATION [platform-tags-ml]: net-new ML resource %q (type: %s) has EMPTY value for required platform tag %q (WS-E gap closure)",
    [addr, rc.type, required_tag],
  )
}

# ---------------------------------------------------------------------------
# Layer 2 — ABAC FLOOR: ML-estate IAM policies touching S3/KMS/Secrets must carry the
# ADR-0028 ABAC tag-match condition. We inspect the rendered policy JSON string on
# aws_iam_policy.after.policy for the ABAC condition key + the principal-tag match.
# ---------------------------------------------------------------------------
_abac_resource_actions := {"s3:", "kms:", "secretsmanager:"}

_policy_grants_data(policy_json) if {
  some action_prefix in _abac_resource_actions
  contains(policy_json, action_prefix)
}

_has_abac_condition(policy_json) if {
  contains(policy_json, "aws:ResourceTag/platform:system")
  contains(policy_json, "aws:PrincipalTag/platform:system")
}

deny contains msg if {
  some addr, rc in input.resource_changes
  rc.type == "aws_iam_policy"
  _is_managed(rc.change.actions)
  _is_ml_estate(rc)
  policy_json := object.get(rc.change.after, "policy", "")
  policy_json != ""
  _policy_grants_data(policy_json)
  not _has_abac_condition(policy_json)
  msg := sprintf(
    "POLICY VIOLATION [platform-abac-ml]: ML-estate IAM policy %q grants S3/KMS/Secrets access without the ADR-0028 ABAC tag-match condition (aws:ResourceTag/platform:system == aws:PrincipalTag/platform:system) — least-privilege ML grants must be ownership-scoped (aws-ml-abac-iam contract)",
    [addr],
  )
}
