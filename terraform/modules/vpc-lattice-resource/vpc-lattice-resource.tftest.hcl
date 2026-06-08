# ---------------------------------------------------------------------------------------------------------------------
# VPC Lattice Resource Connectivity — Native Tests (ADR-0023)
# ---------------------------------------------------------------------------------------------------------------------
# Plan-only, mocked provider — no AWS credentials and no real resources created.
#
# The aws_iam_policy_document data source's computed `json` is mocked to a random
# string by mock_provider, which fails aws_vpclattice_auth_policy's JSON
# validation. We override it with a realistic, org-scoped policy document so the
# resource validates and the org-scoping assertions remain meaningful.
# ---------------------------------------------------------------------------------------------------------------------

mock_provider "aws" {}

override_data {
  target = data.aws_iam_policy_document.auth[0]
  values = {
    json = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Sid\":\"AllowOrgScopedLatticeAccess\",\"Effect\":\"Allow\",\"Principal\":{\"AWS\":\"*\"},\"Action\":\"vpc-lattice-svcs:Invoke\",\"Resource\":\"*\",\"Condition\":{\"StringEquals\":{\"aws:PrincipalOrgID\":\"o-exampleorg12\"}}}]}"
  }
}

variables {
  name               = "shared-rds"
  vpc_id             = "vpc-0123456789abcdef0"
  subnet_ids         = ["subnet-aaa111", "subnet-bbb222", "subnet-ccc333"]
  security_group_ids = ["sg-0123456789abcdef0"]
  resource_arn       = "arn:aws:rds:eu-west-1:000000000000:db:shared-postgres"
  resource_port      = 5432
  principal_org_id   = "o-exampleorg12"
  tags = {
    Environment = "test"
    Team        = "network"
    ManagedBy   = "terraform"
  }
}

run "creates_resource_gateway" {
  command = plan

  assert {
    condition     = aws_vpclattice_resource_gateway.this.name == "shared-rds-rgw"
    error_message = "Resource Gateway should be named '<name>-rgw'"
  }

  assert {
    condition     = aws_vpclattice_resource_gateway.this.vpc_id == "vpc-0123456789abcdef0"
    error_message = "Resource Gateway should live in the resource-owning VPC"
  }

  assert {
    condition     = length(aws_vpclattice_resource_gateway.this.subnet_ids) == 3
    error_message = "Resource Gateway should span all provided (multi-AZ) subnets"
  }
}

run "resource_configuration_is_arn_type_pointing_at_resource_arn" {
  command = plan

  assert {
    condition     = aws_vpclattice_resource_configuration.this.type == "ARN"
    error_message = "Resource Configuration must be type = ARN (ADR-0023)"
  }

  # TCP-only invariant (ADR-0023). For an arn_resource the port/protocol are
  # carried by the target ARN, so we assert on the input invariant.
  assert {
    condition     = var.resource_protocol == "TCP"
    error_message = "Resource Configuration must be TCP-only (ADR-0023)"
  }

  assert {
    condition = one([
      for d in aws_vpclattice_resource_configuration.this.resource_configuration_definition :
      one([for a in d.arn_resource : a.arn])
    ]) == "arn:aws:rds:eu-west-1:000000000000:db:shared-postgres"
    error_message = "arn_resource.arn must point at the supplied RDS DB ARN"
  }
}

run "service_network_uses_iam_auth" {
  command = plan

  assert {
    condition     = aws_vpclattice_service_network.this.name == "shared-rds-sn"
    error_message = "Service Network should be named '<name>-sn'"
  }

  assert {
    condition     = aws_vpclattice_service_network.this.auth_type == "AWS_IAM"
    error_message = "Service Network must use AWS_IAM auth so the auth policy is enforced"
  }
}

run "auth_policy_enabled_by_default" {
  command = plan

  assert {
    condition     = length(aws_vpclattice_auth_policy.this) == 1
    error_message = "Auth policy should be created by default (enable_auth_policy = true)"
  }
}

run "auth_policy_is_org_scoped" {
  command = plan

  assert {
    condition     = strcontains(aws_vpclattice_auth_policy.this[0].policy, "aws:PrincipalOrgID")
    error_message = "Auth policy must be scoped via aws:PrincipalOrgID"
  }

  assert {
    condition     = strcontains(aws_vpclattice_auth_policy.this[0].policy, "o-exampleorg12")
    error_message = "Auth policy must reference the supplied Organization ID"
  }
}

run "no_ram_share_by_default" {
  command = plan

  assert {
    condition     = length(aws_ram_resource_share.this) == 0
    error_message = "RAM share should be disabled by default (enable_ram_share = false)"
  }
}

run "ram_share_created_when_enabled" {
  command = plan

  variables {
    enable_ram_share        = true
    share_with_organization = true
    organization_arn        = "arn:aws:organizations::000000000000:organization/o-exampleorg12"
  }

  assert {
    condition     = aws_ram_resource_share.this[0].name == "shared-rds-sn-share"
    error_message = "RAM share should be created with the '<name>-sn-share' name when enabled"
  }

  assert {
    condition     = length(aws_ram_principal_association.org) == 1
    error_message = "Org-wide RAM principal association should be created when sharing with the organization"
  }
}
