package terraform.platform_tags_ml

import rego.v1

# ---------------------------------------------------------------------------
# Unit tests for the WS-E net-new ML taxonomy + ABAC OPA policy.
# Run: opa test tests/opa/platform_tags_ml.rego tests/opa/platform_tags_ml_test.rego
# (or via conftest in CI). Fixtures are synthetic plan-JSON fragments — no real data.
# ---------------------------------------------------------------------------

# A compliant net-new ML resource (all three tags present) -> no denial.
test_compliant_ml_resource_passes if {
  result := deny with input as {"resource_changes": [{
    "address": "module.gpu.aws_eks_cluster.this",
    "type": "aws_eks_cluster",
    "change": {
      "actions": ["create"],
      "after": {"tags": {
        "platform:system": "ml-platform",
        "platform:component": "gpu-compute",
        "platform:owner": "team-ml-platform",
      }},
    },
  }]}
  count(result) == 0
}

# A net-new ML resource MISSING platform:owner -> exactly one denial.
test_ml_resource_missing_owner_denied if {
  result := deny with input as {"resource_changes": [{
    "address": "module.gpu.aws_eks_node_group.gpu",
    "type": "aws_eks_node_group",
    "change": {
      "actions": ["create"],
      "after": {"tags": {
        "platform:system": "ml-platform",
        "platform:component": "gpu-compute",
      }},
    },
  }]}
  count(result) == 1
}

# An EFA/GPU security group with an EMPTY tag value -> denied.
test_ml_resource_empty_tag_denied if {
  result := deny with input as {"resource_changes": [{
    "address": "module.efa.aws_security_group.efa",
    "type": "aws_security_group",
    "change": {
      "actions": ["create"],
      "after": {"tags": {
        "platform:system": "gpu-fabric",
        "platform:component": "",
        "platform:owner": "team-ml-platform",
      }},
    },
  }]}
  count(result) >= 1
}

# A destroy-only change is ignored (not managed) -> no denial.
test_destroy_only_ignored if {
  result := deny with input as {"resource_changes": [{
    "address": "module.gpu.aws_eks_cluster.this",
    "type": "aws_eks_cluster",
    "change": {
      "actions": ["delete"],
      "after": null,
    },
  }]}
  count(result) == 0
}

# A non-ML resource type is out of this policy's scope (handled by platform_tags.rego).
test_non_ml_type_out_of_scope if {
  result := deny with input as {"resource_changes": [{
    "address": "aws_cloudwatch_log_group.x",
    "type": "aws_cloudwatch_log_group",
    "change": {
      "actions": ["create"],
      "after": {"tags": {}},
    },
  }]}
  count(result) == 0
}

# Layer 2 — an ML IAM policy granting S3 WITH the ABAC condition -> passes.
test_ml_iam_policy_with_abac_passes if {
  result := deny with input as {"resource_changes": [{
    "address": "module.iam.aws_iam_policy.this",
    "type": "aws_iam_policy",
    "change": {
      "actions": ["create"],
      "after": {
        "tags": {
          "platform:system": "ml-platform",
          "platform:component": "ml-iam",
          "platform:owner": "team-ml-platform",
        },
        "policy": "{\"Statement\":[{\"Action\":[\"s3:GetObject\"],\"Condition\":{\"StringEquals\":{\"aws:ResourceTag/platform:system\":\"${aws:PrincipalTag/platform:system}\"}}}]}",
      },
    },
  }]}
  count(result) == 0
}

# Layer 2 — an ML IAM policy granting S3 WITHOUT the ABAC condition -> denied.
test_ml_iam_policy_without_abac_denied if {
  result := deny with input as {"resource_changes": [{
    "address": "module.iam.aws_iam_policy.bad",
    "type": "aws_iam_policy",
    "change": {
      "actions": ["create"],
      "after": {
        "tags": {
          "platform:system": "ml-platform",
          "platform:component": "ml-iam",
          "platform:owner": "team-ml-platform",
        },
        "policy": "{\"Statement\":[{\"Action\":[\"s3:GetObject\"],\"Resource\":\"arn:aws:s3:::x/*\"}]}",
      },
    },
  }]}
  count(result) >= 1
}

# Layer 2 — a non-ML IAM policy (different system) is not subject to the ABAC floor.
test_non_ml_iam_policy_not_abac_gated if {
  result := deny with input as {"resource_changes": [{
    "address": "module.other.aws_iam_policy.x",
    "type": "aws_iam_policy",
    "change": {
      "actions": ["create"],
      "after": {
        "tags": {
          "platform:system": "auth-service",
          "platform:component": "backend",
          "platform:owner": "team-auth",
        },
        "policy": "{\"Statement\":[{\"Action\":[\"s3:GetObject\"],\"Resource\":\"arn:aws:s3:::x/*\"}]}",
      },
    },
  }]}
  # aws_iam_policy IS in the taggable allow-list and HAS all tags, so Layer-1 passes;
  # Layer-2 ABAC floor does not apply (system is not ml-*/gpu-*/security) -> no denial.
  count(result) == 0
}
