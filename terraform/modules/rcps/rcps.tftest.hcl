mock_provider "aws" {}

variables {
  organization_id = "o-testorg12345"
  target_ou_ids   = ["ou-policy-staging-mock"]
  tags = {
    Environment = "test"
    Team        = "security"
    ManagedBy   = "terraform"
  }
}

run "creates_org_perimeter_rcp" {
  command = plan

  assert {
    condition     = aws_organizations_policy.org_perimeter.name == "RCP-DataPerimeter-DenyExternalAccess"
    error_message = "Org-perimeter RCP should be created"
  }
}

run "rcp_is_resource_control_policy_type" {
  command = plan

  assert {
    condition     = aws_organizations_policy.org_perimeter.type == "RESOURCE_CONTROL_POLICY"
    error_message = "Policy type must be RESOURCE_CONTROL_POLICY (the resource-side perimeter)"
  }
}

run "rcp_denies_perimeter_services" {
  command = plan

  assert {
    condition = alltrue([
      for svc in ["s3:*", "sts:*", "kms:*", "secretsmanager:*", "sqs:*"] :
      strcontains(aws_organizations_policy.org_perimeter.content, svc)
    ])
    error_message = "RCP content must deny S3/STS/KMS/SecretsManager/SQS (canonical RCP services per ADR-0017)"
  }
}

run "rcp_matches_org_id_and_carves_out_aws_service" {
  command = plan

  assert {
    condition     = strcontains(aws_organizations_policy.org_perimeter.content, var.organization_id)
    error_message = "RCP must condition on our aws:PrincipalOrgID"
  }

  assert {
    condition     = strcontains(aws_organizations_policy.org_perimeter.content, "aws:PrincipalIsAWSService")
    error_message = "RCP must carve out AWS service principals to avoid breaking log delivery / cross-service calls"
  }
}

run "attaches_to_provided_targets" {
  command = plan

  assert {
    condition     = length(aws_organizations_policy_attachment.org_perimeter) == 1
    error_message = "RCP should attach to exactly the one staged target OU"
  }
}
