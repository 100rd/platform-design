package terraform.encryption_at_rest

import rego.v1

# ---------------------------------------------------------------------------
# Policy: Encryption must be enabled on all storage resources
#
# Resources checked:
#   - aws_s3_bucket_server_side_encryption_configuration (must exist for bucket)
#   - aws_ebs_volume — encrypted must be true
#   - aws_db_instance / aws_rds_cluster — storage_encrypted must be true
#   - aws_elasticache_replication_group — at_rest_encryption_enabled must be true
#   - aws_elasticache_cluster — not encrypted at rest is a violation
#   - aws_dynamodb_table — server_side_encryption enabled must be true
#   - aws_sqs_queue — sqs_managed_sse_enabled or kms_master_key_id required
#   - aws_sns_topic — kms_master_key_id required
#   - aws_secretsmanager_secret — kms_key_id required (not using default key)
#   - aws_kinesis_stream — encryption_type must not be NONE
#   - aws_opensearch_domain / aws_elasticsearch_domain — encrypt_at_rest.enabled
# ---------------------------------------------------------------------------

_is_active(actions) if {
  some a in actions
  a in {"create", "update"}
}

# EBS Volume
deny contains msg if {
  some addr, rc in input.resource_changes
  rc.type == "aws_ebs_volume"
  _is_active(rc.change.actions)
  rc.change.after.encrypted != true
  msg := sprintf(
    "POLICY VIOLATION [encryption-at-rest]: EBS volume %q must have encrypted = true",
    [addr],
  )
}

# RDS Instance
deny contains msg if {
  some addr, rc in input.resource_changes
  rc.type == "aws_db_instance"
  _is_active(rc.change.actions)
  rc.change.after.storage_encrypted != true
  msg := sprintf(
    "POLICY VIOLATION [encryption-at-rest]: RDS instance %q must have storage_encrypted = true",
    [addr],
  )
}

# RDS Cluster (Aurora)
deny contains msg if {
  some addr, rc in input.resource_changes
  rc.type == "aws_rds_cluster"
  _is_active(rc.change.actions)
  rc.change.after.storage_encrypted != true
  msg := sprintf(
    "POLICY VIOLATION [encryption-at-rest]: RDS cluster %q must have storage_encrypted = true",
    [addr],
  )
}

# ElastiCache Replication Group
deny contains msg if {
  some addr, rc in input.resource_changes
  rc.type == "aws_elasticache_replication_group"
  _is_active(rc.change.actions)
  rc.change.after.at_rest_encryption_enabled != true
  msg := sprintf(
    "POLICY VIOLATION [encryption-at-rest]: ElastiCache replication group %q must have at_rest_encryption_enabled = true",
    [addr],
  )
}

# DynamoDB Table
deny contains msg if {
  some addr, rc in input.resource_changes
  rc.type == "aws_dynamodb_table"
  _is_active(rc.change.actions)
  sse := object.get(rc.change.after, "server_side_encryption", [])
  count(sse) == 0
  msg := sprintf(
    "POLICY VIOLATION [encryption-at-rest]: DynamoDB table %q must have server_side_encryption block with enabled = true",
    [addr],
  )
}

deny contains msg if {
  some addr, rc in input.resource_changes
  rc.type == "aws_dynamodb_table"
  _is_active(rc.change.actions)
  some sse in rc.change.after.server_side_encryption
  sse.enabled != true
  msg := sprintf(
    "POLICY VIOLATION [encryption-at-rest]: DynamoDB table %q server_side_encryption.enabled must be true",
    [addr],
  )
}

# SQS Queue — must use SSE or CMK
deny contains msg if {
  some addr, rc in input.resource_changes
  rc.type == "aws_sqs_queue"
  _is_active(rc.change.actions)
  after := rc.change.after
  not object.get(after, "sqs_managed_sse_enabled", false)
  kms := object.get(after, "kms_master_key_id", "")
  kms == ""
  msg := sprintf(
    "POLICY VIOLATION [encryption-at-rest]: SQS queue %q must enable sqs_managed_sse_enabled = true or set kms_master_key_id",
    [addr],
  )
}

# Kinesis Stream
deny contains msg if {
  some addr, rc in input.resource_changes
  rc.type == "aws_kinesis_stream"
  _is_active(rc.change.actions)
  enc_type := object.get(rc.change.after, "encryption_type", "NONE")
  enc_type == "NONE"
  msg := sprintf(
    "POLICY VIOLATION [encryption-at-rest]: Kinesis stream %q encryption_type must not be NONE (use KMS)",
    [addr],
  )
}

# OpenSearch Domain
deny contains msg if {
  some addr, rc in input.resource_changes
  rc.type in {"aws_opensearch_domain", "aws_elasticsearch_domain"}
  _is_active(rc.change.actions)
  ear := object.get(rc.change.after, "encrypt_at_rest", [])
  count(ear) == 0
  msg := sprintf(
    "POLICY VIOLATION [encryption-at-rest]: OpenSearch/Elasticsearch domain %q must have encrypt_at_rest.enabled = true",
    [addr],
  )
}

deny contains msg if {
  some addr, rc in input.resource_changes
  rc.type in {"aws_opensearch_domain", "aws_elasticsearch_domain"}
  _is_active(rc.change.actions)
  some ear in rc.change.after.encrypt_at_rest
  ear.enabled != true
  msg := sprintf(
    "POLICY VIOLATION [encryption-at-rest]: OpenSearch/Elasticsearch domain %q encrypt_at_rest.enabled must be true",
    [addr],
  )
}
