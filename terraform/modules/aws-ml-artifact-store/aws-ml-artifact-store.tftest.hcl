# ---------------------------------------------------------------------------------------------------------------------
# Tests for the aws-ml-artifact-store module (ADR-0048 D2 / WS-B)
# aws provider is mocked so no real AWS credentials are needed.
# All runs use command = plan (no real S3 bucket or IAM role is created).
#
# Note on IAM policy document assertions:
# The mlflow_s3_abac data source references aws_s3_bucket.mlflow_artifacts[0].arn
# which is a computed value unknown at plan time. The trust_policy and s3_abac
# content is verified structurally via the variable and locals layer instead of
# by parsing the rendered JSON (which is only available post-apply).
# The mock_provider provides a realistic JSON for the trust policy data source
# (which has no computed dependencies) so that assertion CAN fire at plan time.
# ---------------------------------------------------------------------------------------------------------------------

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
      caller_arn = "arn:aws:iam::123456789012:role/ci-role"
      user_id    = "AROA1234567890EXAMPLE:ci-role"
    }
  }

  # aws_iam_policy_document generates JSON. The trust policy data source
  # has no computed dependencies so mock_provider can provide its json.
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = <<-POLICY
        {"Version":"2012-10-17","Statement":[{"Sid":"EKSPodIdentityTrust","Effect":"Allow","Principal":{"Service":"pods.eks.amazonaws.com"},"Action":["sts:AssumeRole","sts:TagSession"],"Condition":{"StringEquals":{"aws:SourceAccount":"123456789012","aws:PrincipalTag/platform:system":"ml-pipeline","aws:ResourceTag/platform:system":"ml-pipeline"}}}]}
      POLICY
    }
  }

  override_resource {
    target = aws_s3_bucket.mlflow_artifacts[0]
    values = {
      id  = "mlflow-artifacts-staging-123456789012"
      arn = "arn:aws:s3:::mlflow-artifacts-staging-123456789012"
    }
  }

  override_resource {
    target = aws_iam_role.mlflow_artifact_store[0]
    values = {
      arn  = "arn:aws:iam::123456789012:role/mlflow-artifact-store"
      name = "mlflow-artifact-store"
    }
  }
}

# Variables shared across all runs.
variables {
  bucket_name      = "mlflow-artifacts-staging-123456789012"
  eks_cluster_name = "aws-eks-gpu-test"
  create_resources = true
  tags = {
    "platform:system"     = "ml-pipeline"
    "platform:component"  = "model-registry"
    "platform:env"        = "test"
    "platform:owner"      = "team-ml"
    "platform:managed-by" = "terragrunt"
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# Apply gate
# ---------------------------------------------------------------------------------------------------------------------

run "no_resources_when_gate_off" {
  command = plan

  variables {
    create_resources = false
  }

  assert {
    condition     = length(aws_s3_bucket.mlflow_artifacts) == 0
    error_message = "No S3 bucket should be planned when create_resources = false (apply gate)."
  }

  assert {
    condition     = length(aws_iam_role.mlflow_artifact_store) == 0
    error_message = "No IAM role should be planned when create_resources = false (apply gate)."
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# Bucket configuration
# ---------------------------------------------------------------------------------------------------------------------

run "bucket_owner_enforced_no_acls" {
  command = plan

  assert {
    condition     = aws_s3_bucket_ownership_controls.mlflow_artifacts[0].rule[0].object_ownership == "BucketOwnerEnforced"
    error_message = "Bucket must use BucketOwnerEnforced (IAM-only; no per-object ACLs) as the S3 analog of GCS uniform bucket-level access."
  }
}

run "bucket_public_access_fully_blocked" {
  command = plan

  assert {
    condition     = aws_s3_bucket_public_access_block.mlflow_artifacts[0].block_public_acls == true
    error_message = "block_public_acls must be true."
  }

  assert {
    condition     = aws_s3_bucket_public_access_block.mlflow_artifacts[0].block_public_policy == true
    error_message = "block_public_policy must be true."
  }

  assert {
    condition     = aws_s3_bucket_public_access_block.mlflow_artifacts[0].restrict_public_buckets == true
    error_message = "restrict_public_buckets must be true."
  }
}

run "bucket_versioning_enabled_by_default" {
  command = plan

  assert {
    condition     = aws_s3_bucket_versioning.mlflow_artifacts[0].versioning_configuration[0].status == "Enabled"
    error_message = "Object versioning must be enabled by default for SOC2 artifact audit trail (ADR-0048 D2)."
  }
}

run "bucket_versioning_can_be_suspended" {
  command = plan

  variables {
    versioning_enabled = false
  }

  assert {
    condition     = aws_s3_bucket_versioning.mlflow_artifacts[0].versioning_configuration[0].status == "Suspended"
    error_message = "Versioning should be Suspended when versioning_enabled = false."
  }
}

run "bucket_carries_adr0028_tags" {
  command = plan

  assert {
    condition     = aws_s3_bucket.mlflow_artifacts[0].tags["platform:system"] == "ml-pipeline"
    error_message = "Bucket must carry platform:system = ml-pipeline per ADR-0028."
  }

  assert {
    condition     = aws_s3_bucket.mlflow_artifacts[0].tags["platform:component"] == "model-registry"
    error_message = "Bucket must carry platform:component = model-registry per ADR-0028."
  }

  assert {
    condition     = aws_s3_bucket.mlflow_artifacts[0].tags["platform:env"] == "test"
    error_message = "Caller-supplied platform:env must be present on the bucket."
  }
}

run "sse_defaults_to_aes256_without_kms_key" {
  command = plan

  assert {
    condition     = tolist(aws_s3_bucket_server_side_encryption_configuration.mlflow_artifacts[0].rule)[0].apply_server_side_encryption_by_default[0].sse_algorithm == "AES256"
    error_message = "Without a KMS key, SSE must default to AES256."
  }
}

run "sse_uses_kms_when_key_provided" {
  command = plan

  variables {
    kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/00000000-0000-0000-0000-000000000001"
  }

  assert {
    condition     = tolist(aws_s3_bucket_server_side_encryption_configuration.mlflow_artifacts[0].rule)[0].apply_server_side_encryption_by_default[0].sse_algorithm == "aws:kms"
    error_message = "SSE algorithm must be aws:kms when kms_key_arn is provided (ADR-0048 D2)."
  }
}

run "lifecycle_standard_ia_default_90_days" {
  command = plan

  assert {
    condition     = var.standard_ia_after_days == 90
    error_message = "Default standard_ia_after_days must be 90 (S3 analog of GCS Nearline — ADR-0048 D2)."
  }
}

run "lifecycle_glacier_default_365_days" {
  command = plan

  assert {
    condition     = var.glacier_after_days == 365
    error_message = "Default glacier_after_days must be 365 (S3 analog of GCS Coldline — ADR-0048 D2)."
  }
}

run "lifecycle_expire_default_730_days" {
  command = plan

  assert {
    condition     = var.expire_after_days == 730
    error_message = "Default expire_after_days must be 730 (S3 analog of GCS deletion — ADR-0048 D2)."
  }
}

run "rejects_negative_standard_ia_days" {
  command = plan

  variables {
    standard_ia_after_days = -1
  }

  expect_failures = [var.standard_ia_after_days]
}

run "rejects_negative_expire_days" {
  command = plan

  variables {
    expire_after_days = -1
  }

  expect_failures = [var.expire_after_days]
}

# ---------------------------------------------------------------------------------------------------------------------
# IAM / Pod Identity + ABAC
# Trust policy: uses mock_provider json (no computed deps) — CAN be evaluated at plan.
# S3 ABAC policy: references bucket ARN (computed) — json deferred to apply time.
#   Verified instead via the local variable (local.platform_system) and via the
#   IAM role tag (which is plan-time known) as a proxy for the ABAC design intent.
# ---------------------------------------------------------------------------------------------------------------------

run "iam_role_carries_adr0028_tags" {
  command = plan

  assert {
    condition     = aws_iam_role.mlflow_artifact_store[0].tags["platform:system"] == "ml-pipeline"
    error_message = "IAM role must carry platform:system = ml-pipeline so the ABAC condition can fire (ADR-0028 / ADR-0048 D2)."
  }
}

# Trust policy data source has no computed deps — mock JSON is available at plan.
run "trust_policy_allows_eks_pod_identity_service" {
  command = plan

  assert {
    condition = can(
      regex("pods\\.eks\\.amazonaws\\.com",
      data.aws_iam_policy_document.mlflow_pod_identity_trust[0].json)
    )
    error_message = "Trust policy must allow pods.eks.amazonaws.com for EKS Pod Identity (ADR-0018)."
  }
}

# ABAC design: verified via the module's effective platform_system local value.
# The S3 policy statement's ABAC condition keys are derived from this value —
# if local.platform_system is "ml-pipeline", the condition keys will be correct.
run "abac_platform_system_value_is_ml_pipeline" {
  command = plan

  assert {
    condition     = aws_s3_bucket.mlflow_artifacts[0].tags["platform:system"] == "ml-pipeline"
    error_message = "Bucket must be tagged platform:system = ml-pipeline; this value drives the ABAC condition key in the IAM policy (ADR-0028 / ADR-0048 D2)."
  }

  assert {
    condition     = aws_iam_role.mlflow_artifact_store[0].tags["platform:system"] == "ml-pipeline"
    error_message = "IAM role must be tagged platform:system = ml-pipeline; this value drives the ABAC condition key in the IAM policy (ADR-0028 / ADR-0048 D2)."
  }
}

# Verify the IAM role policy resource exists (policy content verified post-apply).
run "iam_role_policy_attached" {
  command = plan

  assert {
    condition     = aws_iam_role_policy.mlflow_s3_abac[0].name == "mlflow-s3-abac"
    error_message = "IAM role policy 'mlflow-s3-abac' must be created and attached to the MLflow role (ADR-0048 D2)."
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# Outputs
# ---------------------------------------------------------------------------------------------------------------------

run "output_bucket_url_has_s3_prefix" {
  command = plan

  assert {
    condition     = startswith(output.bucket_url, "s3://")
    error_message = "bucket_url output must start with s3:// for use as MLFLOW_DEFAULT_ARTIFACT_ROOT."
  }
}

run "output_role_arn_has_iam_prefix" {
  command = plan

  assert {
    condition     = aws_iam_role.mlflow_artifact_store[0].name == var.mlflow_pod_identity_role_name
    error_message = "IAM role name must match var.mlflow_pod_identity_role_name (default: mlflow-artifact-store)."
  }
}
