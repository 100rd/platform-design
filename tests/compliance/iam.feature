Feature: IAM best practices and access control
  As a security engineer
  I want to ensure IAM policies follow least-privilege principles
  So that we comply with PCI-DSS Requirements 7.1 and 7.2

  Scenario: IAM policies must not use wildcard actions
    Given I have aws_iam_policy defined
    When it has policy
    Then it must have Statement
    Then it must not have "Action" that includes "*"

  Scenario: IAM policies must not use wildcard resources with dangerous actions
    Given I have aws_iam_policy_document defined
    When it has statement
    Then it must have actions
    And its value must not be "*"

  Scenario: IAM roles must have description
    Given I have aws_iam_role defined
    Then it must have description

  Scenario: Password policy must enforce minimum length
    Given I have aws_iam_account_password_policy defined
    Then it must have minimum_password_length
    And its value must be greater than 6

  Scenario: Password policy must require complexity
    Given I have aws_iam_account_password_policy defined
    Then it must have require_lowercase_characters
    And its value must be true
    Then it must have require_uppercase_characters
    And its value must be true
    Then it must have require_numbers
    And its value must be true
    Then it must have require_symbols
    And its value must be true

  Scenario: Password policy must enforce expiration within 90 days
    Given I have aws_iam_account_password_policy defined
    Then it must have max_password_age
    And its value must be less than or equal to 90

  Scenario: Password policy must prevent password reuse
    Given I have aws_iam_account_password_policy defined
    Then it must have password_reuse_prevention
    And its value must be greater than 3

  Scenario: MFA enforcement policy must exist
    Given I have aws_iam_policy defined
    When its name includes "EnforceMFA"
    Then it must have policy

  Scenario: IAM Access Analyzer must be enabled
    Given I have aws_accessanalyzer_analyzer defined
    Then it must have type

  Scenario: Service account roles must use OIDC conditions
    Given I have aws_iam_role defined
    When its name includes "irsa"
    Then it must have assume_role_policy

  Scenario: SCPs must exist for organization security
    Given I have aws_organizations_policy defined
    Then it must have content
    Then it must have type
    And its value must be "SERVICE_CONTROL_POLICY"
