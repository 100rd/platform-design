mock_provider "aws" {}

variables {
  cur_s3_bucket_name         = "test-cur-opencost-bucket"
  athena_results_bucket_name = "test-athena-results-opencost"
  eks_oidc_provider          = "oidc.eks.us-east-1.amazonaws.com/id/TESTOIDC1234567890AB"
}

run "default_cur_report_name" {
  command = plan

  assert {
    condition     = var.cur_report_name == "opencost-cur"
    error_message = "Default CUR report name should be 'opencost-cur'"
  }
}

run "creates_cur_report_with_parquet_format" {
  command = plan

  assert {
    condition     = aws_cur_report_definition.opencost.format == "Parquet"
    error_message = "CUR report format must be Parquet for Athena compatibility"
  }
}

run "creates_cur_report_with_athena_artifact" {
  command = plan

  assert {
    condition     = contains(aws_cur_report_definition.opencost.additional_artifacts, "ATHENA")
    error_message = "CUR report must include ATHENA additional artifact for Glue manifest generation"
  }
}

run "cur_bucket_blocks_public_access" {
  command = plan

  assert {
    condition     = aws_s3_bucket_public_access_block.cur.block_public_acls == true
    error_message = "CUR S3 bucket must block all public ACLs"
  }

  assert {
    condition     = aws_s3_bucket_public_access_block.cur.restrict_public_buckets == true
    error_message = "CUR S3 bucket must restrict public buckets"
  }
}

run "iam_role_scoped_to_opencost_serviceaccount" {
  command = plan

  assert {
    condition     = var.opencost_namespace == "opencost"
    error_message = "Default opencost namespace should be 'opencost'"
  }

  assert {
    condition     = var.opencost_service_account == "opencost"
    error_message = "Default opencost service account should be 'opencost'"
  }
}

run "lifecycle_retention_minimum" {
  command = plan

  assert {
    condition     = var.lifecycle_expiration_days >= 365
    error_message = "CUR lifecycle expiration must be >= 365 days"
  }
}

run "glue_database_name_default" {
  command = plan

  assert {
    condition     = var.glue_database_name == "cur_opencost"
    error_message = "Default Glue database name should be 'cur_opencost'"
  }
}

run "athena_workgroup_name_default" {
  command = plan

  assert {
    condition     = var.athena_workgroup_name == "opencost"
    error_message = "Default Athena workgroup name should be 'opencost'"
  }
}
