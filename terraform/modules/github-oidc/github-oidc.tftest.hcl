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
