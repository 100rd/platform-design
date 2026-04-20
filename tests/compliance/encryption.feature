Feature: Encryption requirements for all data stores and transport
  As a security engineer
  I want to ensure all data is encrypted at rest and in transit
  So that we comply with PCI-DSS Requirements 3.4 and 4.1

  Scenario: S3 buckets must have server-side encryption enabled
    Given I have aws_s3_bucket_server_side_encryption_configuration defined
    Then it must have rule
    Then it must have apply_server_side_encryption_by_default
    And it must have sse_algorithm
    And its value must match the "aws:kms|AES256" regex

  Scenario: S3 buckets must use KMS encryption
    Given I have aws_s3_bucket_server_side_encryption_configuration defined
    Then it must have rule
    Then it must have apply_server_side_encryption_by_default
    And it must have sse_algorithm
    And its value must be "aws:kms"

  Scenario: S3 bucket key must be enabled for cost optimization
    Given I have aws_s3_bucket_server_side_encryption_configuration defined
    Then it must have rule
    And it must have bucket_key_enabled
    And its value must be true

  Scenario: RDS instances must have storage encryption enabled
    Given I have aws_db_instance defined
    Then it must have storage_encrypted
    And its value must be true

  Scenario: EBS encryption by default must be enabled
    Given I have aws_ebs_encryption_by_default defined
    Then it must have enabled
    And its value must be true

  Scenario: DynamoDB tables must have server-side encryption
    Given I have aws_dynamodb_table defined
    Then it must have server_side_encryption
    And it must have enabled
    And its value must be true

  Scenario: KMS keys must have automatic rotation enabled
    Given I have aws_kms_key defined
    Then it must have enable_key_rotation
    And its value must be true

  Scenario: ECR repositories must have encryption configured
    Given I have aws_ecr_repository defined
    Then it must have encryption_configuration
    And it must have encryption_type

  Scenario: ElastiCache must use in-transit encryption
    Given I have aws_elasticache_replication_group defined
    Then it must have transit_encryption_enabled
    And its value must be true

  Scenario: SQS queues must have encryption enabled
    Given I have aws_sqs_queue defined
    Then it must have sqs_managed_sse_enabled

  Scenario: CloudTrail must use KMS encryption
    Given I have aws_cloudtrail defined
    Then it must have kms_key_id
    And its value must not be null

  Scenario: CloudWatch Log Groups used by CloudTrail must be KMS encrypted
    Given I have aws_cloudwatch_log_group defined
    When its name includes "cloudtrail"
    Then it must have kms_key_id
    And its value must not be null
