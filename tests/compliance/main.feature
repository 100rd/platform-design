Feature: Core compliance rules for all infrastructure resources
  As a platform engineer
  I want to ensure all resources follow organizational compliance standards
  So that our infrastructure meets security and operational requirements

  Scenario: All resources must be managed by Terraform
    Given I have resource that supports tags
    Then it must contain tags
    Then it must have tags

  Scenario: Resources must have required base tags
    Given I have resource that supports tags
    When it has tags
    Then it must have tags
    And its value must not be null

  Scenario: Terraform required version must be pinned
    Given I have terraform block configured
    Then it must contain required_version

  Scenario: Provider versions must be constrained
    Given I have provider configured
    When its name is "aws"
    Then it must contain version

  Scenario: All S3 buckets must have force_destroy disabled in production
    Given I have aws_s3_bucket defined
    Then it must contain force_destroy
    And its value must be false

  Scenario: Prevent destroy lifecycle should be set on critical resources
    Given I have aws_kms_key defined
    Then it must have lifecycle
    And it must have prevent_destroy

  Scenario: All CloudWatch log groups must have retention configured
    Given I have aws_cloudwatch_log_group defined
    Then it must contain retention_in_days
    And its value must be greater than 0
