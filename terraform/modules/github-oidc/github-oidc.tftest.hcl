mock_provider "aws" {}

variables {
  project      = "test-project"
  account_name = "dev"
  repository   = "100rd/platform-design"
  tags = {
    Environment = "test"
    Team        = "platform"
    ManagedBy   = "terraform"
  }
}

run "default_branch" {
  command = plan

  assert {
    condition     = var.branch == "main"
    error_message = "Default branch should be main"
  }
}

run "empty_extra_subjects_by_default" {
  command = plan

  assert {
    condition     = length(var.extra_subjects) == 0
    error_message = "No extra OIDC subjects should be defined by default"
  }
}

# Issue #173 regression guard: a non-dedicated account (dev) must get the
# scoped "workload" policy, NOT AdministratorAccess. This survives the v6.x
# migration because the role's policies map references local.terraform_scoped_policy_arn.
run "terraform_role_uses_scoped_workload_policy_not_admin" {
  command = plan

  assert {
    condition     = length(aws_iam_policy.workload) == 1
    error_message = "Non-dedicated account (dev) must create the scoped workload policy"
  }

  assert {
    condition     = aws_iam_policy.workload[0].name == "test-project-dev-terraform-scoped"
    error_message = "Workload policy name must follow the scoped naming convention"
  }

  assert {
    condition     = length(aws_iam_policy.log_archive) == 0 && length(aws_iam_policy.network) == 0 && length(aws_iam_policy.shared) == 0
    error_message = "Dedicated account policies must not be created for a workload account"
  }
}

# Dedicated-account routing still works after the migration.
run "log_archive_account_uses_dedicated_policy" {
  command = plan

  variables {
    account_name = "log-archive"
  }

  assert {
    condition     = length(aws_iam_policy.log_archive) == 1
    error_message = "log-archive account must create its dedicated scoped policy"
  }

  assert {
    condition     = length(aws_iam_policy.workload) == 0
    error_message = "log-archive account must NOT fall through to the workload policy"
  }
}

# The ECR push policy is created and named deterministically (unchanged by migration).
run "ecr_push_policy_created" {
  command = plan

  assert {
    condition     = aws_iam_policy.ecr_push.name == "test-project-dev-ecr-push"
    error_message = "ECR push policy must be created with the expected name"
  }
}
