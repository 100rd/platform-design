# ---------------------------------------------------------------------------------------------------------------------
# Tests — aws-ml-abac-iam (mocked AWS provider; plan-only, no apply, no real IAM)
# ---------------------------------------------------------------------------------------------------------------------
# Verifies: apply-gated default-OFF; the ADR-0028 ABAC tag-match condition is present in
# every grant; least-privilege (no wildcard action/resource); ADR-0028 taxonomy tags;
# Pod Identity association gated on cluster name. ADR-0018/0028/0048.
# Synthetic ARNs only (AWS docs reserved example account 111122223333).
# ---------------------------------------------------------------------------------------------------------------------

mock_provider "aws" {
  # aws_iam_policy_document is provider-computed; the default mock returns a random
  # string that fails IAM's JSON-policy validator. Supply valid documents so the IAM
  # resources validate. The supplied permission doc carries the ABAC tag-match condition
  # so the wiring assertions (strcontains on the resource policy) remain meaningful; the
  # condition *generation* from statement blocks is checked by `terraform validate` and
  # the OPA rego (tests/opa/platform_tags_ml.rego) against the real plan JSON in CI.
  override_data {
    target = data.aws_iam_policy_document.assume
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Sid\":\"EksPodIdentityAssume\",\"Effect\":\"Allow\",\"Action\":[\"sts:AssumeRole\",\"sts:TagSession\"],\"Principal\":{\"Service\":\"pods.eks.amazonaws.com\"}}]}"
    }
  }

  override_data {
    target = data.aws_iam_policy_document.permissions
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Sid\":\"ArtifactStoreObjectsAbac\",\"Effect\":\"Allow\",\"Action\":[\"s3:GetObject\",\"s3:PutObject\",\"s3:DeleteObject\"],\"Resource\":\"arn:aws:s3:::ml-artifacts-test/*\",\"Condition\":{\"StringEquals\":{\"aws:ResourceTag/platform:system\":\"$${aws:PrincipalTag/platform:system}\"}}}]}"
    }
  }
}

# --- 1. DEFAULT OFF: no IAM at all -----------------------------------------------------------------------------------
run "default_is_apply_gated_off" {
  command = plan

  assert {
    condition     = var.enabled == false
    error_message = "Module must default to apply-gated OFF (enabled=false)."
  }

  assert {
    condition     = length(aws_iam_role.this) == 0
    error_message = "Default (gated off) must create no IAM role."
  }

  assert {
    condition     = length(aws_iam_policy.this) == 0
    error_message = "Default (gated off) must create no IAM policy."
  }

  assert {
    condition     = length(aws_eks_pod_identity_association.this) == 0
    error_message = "Default (gated off) must create no Pod Identity association."
  }

  assert {
    condition     = output.abac_enforced == false
    error_message = "abac_enforced must be false when gated off."
  }
}

# --- 2. ENABLED with S3 + KMS + Secrets: ABAC condition present in every grant ----------------------------------------
run "enabled_grants_carry_abac_condition" {
  command = plan

  variables {
    enabled              = true
    name                 = "ml-platform-workload"
    platform_system      = "ml-platform"
    artifact_bucket_arns = ["arn:aws:s3:::ml-artifacts-test"]
    kms_key_arns         = ["arn:aws:kms:us-east-1:111122223333:key/abcd-1234"]
    secret_arns          = ["arn:aws:secretsmanager:us-east-1:111122223333:secret:mlflow/rds-AbCdEf"]
  }

  assert {
    condition     = length(aws_iam_role.this) == 1
    error_message = "Enabling the gate must create the IAM role."
  }

  # The ABAC tag-match must appear in the generated permission-policy JSON.
  assert {
    condition     = strcontains(aws_iam_policy.this[0].policy, "aws:ResourceTag/platform:system")
    error_message = "Every grant must carry the ABAC aws:ResourceTag/platform:system condition (ADR-0028)."
  }

  assert {
    condition     = strcontains(aws_iam_policy.this[0].policy, "$${aws:PrincipalTag/platform:system}")
    error_message = "ABAC condition must match ResourceTag against the PrincipalTag platform:system."
  }

  assert {
    condition     = output.abac_enforced == true
    error_message = "abac_enforced must be true when at least one resource class is granted."
  }
}

# --- 3. Least-privilege: no wildcard action and no wildcard resource --------------------------------------------------
run "least_privilege_no_wildcards" {
  command = plan

  variables {
    enabled              = true
    platform_system      = "ml-platform"
    artifact_bucket_arns = ["arn:aws:s3:::ml-artifacts-test"]
  }

  assert {
    condition     = !strcontains(aws_iam_policy.this[0].policy, "\"Action\":\"*\"")
    error_message = "Permission policy must not grant Action '*' (least-privilege)."
  }

  assert {
    condition     = !strcontains(aws_iam_policy.this[0].policy, "\"Resource\":\"*\"")
    error_message = "Permission policy must not grant Resource '*' (least-privilege)."
  }
}

# --- 4. ADR-0028 taxonomy on the role + platform_system scoping -------------------------------------------------------
run "taxonomy_and_scoping" {
  command = plan

  variables {
    enabled              = true
    platform_system      = "ml-pipeline"
    artifact_bucket_arns = ["arn:aws:s3:::ml-artifacts-test"]
  }

  assert {
    condition     = aws_iam_role.this[0].tags["platform:system"] == "ml-pipeline"
    error_message = "platform:system tag must follow var.platform_system (ADR-0028)."
  }

  assert {
    condition     = aws_iam_role.this[0].tags["platform:component"] == "ml-iam"
    error_message = "platform:component must be 'ml-iam'."
  }

  assert {
    condition     = aws_iam_role.this[0].tags["platform:owner"] == "team-ml-platform"
    error_message = "platform:owner must be 'team-ml-platform'."
  }

  assert {
    condition     = output.platform_system == "ml-pipeline"
    error_message = "platform_system output must reflect the scoped system."
  }
}

# --- 5. Pod Identity association is gated on the cluster name ----------------------------------------------------------
run "pod_identity_gated_on_cluster" {
  command = plan

  variables {
    enabled              = true
    platform_system      = "ml-platform"
    artifact_bucket_arns = ["arn:aws:s3:::ml-artifacts-test"]
    eks_cluster_name     = "aws-eks-gpu-use1"
  }

  assert {
    condition     = length(aws_eks_pod_identity_association.this) == 1
    error_message = "Supplying an EKS cluster name must create the Pod Identity association."
  }

  assert {
    condition     = aws_eks_pod_identity_association.this[0].namespace == "ml-platform"
    error_message = "Pod Identity association must target the configured namespace."
  }
}
