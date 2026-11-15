mock_provider "aws" {}

variables {
  # Staged first (Policy-Staging OU only) per ADR-0017 step 3.
  target_ou_ids = ["ou-policy-staging-mock"]
  tags = {
    Environment = "management"
    ManagedBy   = "terraform"
    ADR         = "0017"
  }
}

run "creates_ec2_declarative_policy" {
  command = plan

  assert {
    condition     = aws_organizations_policy.ec2.type == "DECLARATIVE_POLICY_EC2"
    error_message = "Policy type must be DECLARATIVE_POLICY_EC2."
  }
}

run "enforces_imdsv2_and_block_public_sharing" {
  command = plan

  assert {
    condition     = strcontains(aws_organizations_policy.ec2.content, "http_tokens")
    error_message = "Must set instance_metadata_defaults.http_tokens (IMDSv2)."
  }
  assert {
    condition     = strcontains(aws_organizations_policy.ec2.content, "block_new_sharing")
    error_message = "Must block public EBS-snapshot/AMI sharing (block_new_sharing)."
  }
  assert {
    condition     = strcontains(aws_organizations_policy.ec2.content, "@@assign")
    error_message = "Declarative policy must use the @@assign operator."
  }
}

run "allowed_images_audit_mode_default" {
  command = plan

  assert {
    condition     = strcontains(aws_organizations_policy.ec2.content, "audit_mode")
    error_message = "Allowed-images should default to audit_mode for staged rollout."
  }
}

run "staged_single_attachment" {
  command = plan

  assert {
    condition     = length(aws_organizations_policy_attachment.ec2) == 1
    error_message = "Staged rollout (step 3) attaches to the Policy-Staging OU only."
  }
}

run "imdsv2_can_be_audited_off" {
  command = plan

  variables {
    require_imdsv2 = false
  }

  assert {
    condition     = !strcontains(aws_organizations_policy.ec2.content, "http_tokens")
    error_message = "Disabling require_imdsv2 must drop the instance_metadata_defaults block."
  }
}
