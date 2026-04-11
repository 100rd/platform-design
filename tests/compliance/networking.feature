Feature: Network security rules for all infrastructure
  As a network security engineer
  I want to ensure no insecure network configurations exist
  So that we prevent unauthorized access to our systems

  Scenario: Security groups must not allow unrestricted SSH access
    Given I have aws_security_group_rule defined
    When it has ingress
    Then it must not have cidr_blocks that include "0.0.0.0/0"
    When its from_port is 22
    And its to_port is 22

  Scenario: Security groups must not allow unrestricted RDP access
    Given I have aws_security_group_rule defined
    When it has ingress
    Then it must not have cidr_blocks that include "0.0.0.0/0"
    When its from_port is 3389
    And its to_port is 3389

  Scenario: Security groups must not allow unrestricted database access
    Given I have aws_security_group_rule defined
    When it has ingress
    Then it must not have cidr_blocks that include "0.0.0.0/0"
    When its from_port is 5432
    And its to_port is 5432

  Scenario: S3 buckets must block all public access
    Given I have aws_s3_bucket_public_access_block defined
    Then it must have block_public_acls
    And its value must be true
    Then it must have block_public_policy
    And its value must be true
    Then it must have ignore_public_acls
    And its value must be true
    Then it must have restrict_public_buckets
    And its value must be true

  Scenario: S3 account-level public access block must be enabled
    Given I have aws_s3_account_public_access_block defined
    Then it must have block_public_acls
    And its value must be true
    Then it must have block_public_policy
    And its value must be true

  Scenario: VPC flow logs must be enabled
    Given I have aws_flow_log defined
    Then it must have traffic_type
    And its value must be "ALL"

  Scenario: VPC DNS support must be enabled
    Given I have aws_vpc defined
    Then it must have enable_dns_support
    And its value must be true

  Scenario: VPC DNS hostnames must be enabled
    Given I have aws_vpc defined
    Then it must have enable_dns_hostnames
    And its value must be true

  Scenario: EKS cluster endpoint should not be publicly accessible
    Given I have aws_eks_cluster defined
    When it has vpc_config
    Then it must have endpoint_private_access
    And its value must be true

  Scenario: CloudTrail trail must be multi-region
    Given I have aws_cloudtrail defined
    Then it must have is_multi_region_trail
    And its value must be true

  Scenario: S3 buckets must enforce TLS via bucket policy
    Given I have aws_s3_bucket_policy defined
    Then it must have policy

  Scenario: WAF WebACL must be in REGIONAL scope
    Given I have aws_wafv2_web_acl defined
    Then it must have scope
    And its value must be "REGIONAL"
