# ---------------------------------------------------------------------------------------------------------------------
# cost-cur-export module outputs
# ---------------------------------------------------------------------------------------------------------------------
# These outputs feed directly into the OpenCost cloud-integration.json secret
# that ESO materialises at /opencost/cloud-integration in AWS Secrets Manager.
#
# cloud-integration.json shape (all fields from this module):
#   {
#     "aws": [{
#       "bucket":    <cur_s3_bucket_name>,
#       "region":    <aws_region>,
#       "database":  <glue_database_name>,
#       "table":     <glue_table_name>,
#       "workgroup": <athena_workgroup_name>,
#       "account":   <aws_account_id>
#     }]
#   }
# ---------------------------------------------------------------------------------------------------------------------

output "cur_s3_bucket_name" {
  description = "Name of the S3 bucket receiving CUR Parquet files. Maps to cloud-integration.json 'bucket'."
  value       = aws_s3_bucket.cur.bucket
}

output "cur_s3_bucket_arn" {
  description = "ARN of the CUR S3 bucket."
  value       = aws_s3_bucket.cur.arn
}

output "athena_results_bucket_name" {
  description = "Name of the Athena query-results S3 bucket."
  value       = aws_s3_bucket.athena_results.bucket
}

output "glue_database_name" {
  description = "Glue catalog database name. Maps to cloud-integration.json 'database'."
  value       = aws_glue_catalog_database.cur.name
}

output "glue_table_name" {
  description = "Glue table name (derived from CUR report name). Maps to cloud-integration.json 'table'."
  value       = local.glue_table_name
}

output "athena_workgroup_name" {
  description = "Athena workgroup name. Maps to cloud-integration.json 'workgroup'."
  value       = aws_athena_workgroup.opencost.name
}

output "athena_workgroup_arn" {
  description = "Athena workgroup ARN."
  value       = aws_athena_workgroup.opencost.arn
}

output "aws_account_id" {
  description = "AWS account ID. Maps to cloud-integration.json 'account'."
  value       = local.account_id
}

output "opencost_irsa_role_arn" {
  description = "IAM role ARN for IRSA. Annotate the OpenCost ServiceAccount with: eks.amazonaws.com/role-arn = <this value>."
  value       = aws_iam_role.opencost.arn
}

output "opencost_irsa_role_name" {
  description = "IAM role name for the OpenCost IRSA role."
  value       = aws_iam_role.opencost.name
}

output "kms_key_arn" {
  description = "ARN of the KMS CMK used for CUR + Athena SSE-KMS encryption (module-created or caller-supplied)."
  value       = local.kms_key_arn
}

output "kms_key_alias" {
  description = "Alias of the module-created KMS CMK. Empty string when kms_key_arn was supplied by the caller."
  value       = var.kms_key_arn == "" ? aws_kms_alias.billing[0].name : ""
}
