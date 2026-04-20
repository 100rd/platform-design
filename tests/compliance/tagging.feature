Feature: Required tags for all infrastructure resources
  As a platform engineer
  I want to ensure all resources have mandatory tags
  So that we can track ownership, cost, and compliance

  Scenario Outline: Resources must have Environment tag
    Given I have <resource_type> defined
    When it has tags
    Then it must have tags
    Then it must contain "Environment"

    Examples:
      | resource_type                   |
      | aws_s3_bucket                   |
      | aws_kms_key                     |
      | aws_dynamodb_table              |
      | aws_sqs_queue                   |
      | aws_ecr_repository              |
      | aws_cloudtrail                  |
      | aws_guardduty_detector          |
      | aws_cloudwatch_log_group        |
      | aws_iam_policy                  |
      | aws_ec2_transit_gateway         |
      | aws_wafv2_web_acl               |
      | aws_security_group              |

  Scenario Outline: Resources must have Team tag
    Given I have <resource_type> defined
    When it has tags
    Then it must have tags
    Then it must contain "Team"

    Examples:
      | resource_type                   |
      | aws_s3_bucket                   |
      | aws_kms_key                     |
      | aws_dynamodb_table              |
      | aws_sqs_queue                   |
      | aws_ecr_repository              |

  Scenario Outline: Resources must have ManagedBy tag
    Given I have <resource_type> defined
    When it has tags
    Then it must have tags
    Then it must contain "ManagedBy"

    Examples:
      | resource_type                   |
      | aws_s3_bucket                   |
      | aws_kms_key                     |
      | aws_dynamodb_table              |
      | aws_sqs_queue                   |
      | aws_ecr_repository              |

  Scenario: KMS keys must have pci-dss-scope tag
    Given I have aws_kms_key defined
    When it has tags
    Then it must have tags
    Then it must contain "pci-dss-scope"

  Scenario: CloudTrail resources must have compliance tags
    Given I have aws_cloudtrail defined
    When it has tags
    Then it must have tags
    Then it must contain "pci-dss-scope"
