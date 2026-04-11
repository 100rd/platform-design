mock_provider "aws" {}

variables {
  repositories = ["app-api", "app-worker"]
  tags = {
    Environment = "test"
    Team        = "platform"
    ManagedBy   = "terraform"
  }
}

run "creates_repositories" {
  command = plan

  assert {
    condition     = length(aws_ecr_repository.this) == 2
    error_message = "Should create 2 ECR repositories"
  }
}

run "image_scanning_enabled" {
  command = plan

  assert {
    condition     = aws_ecr_repository.this["app-api"].image_scanning_configuration[0].scan_on_push == true
    error_message = "Image scanning on push should be enabled"
  }
}

run "immutable_tags_by_default" {
  command = plan

  assert {
    condition     = aws_ecr_repository.this["app-api"].image_tag_mutability == "IMMUTABLE"
    error_message = "Image tags should be immutable by default"
  }
}

run "kms_encryption_by_default" {
  command = plan

  assert {
    condition     = var.encryption_type == "KMS"
    error_message = "Default encryption type should be KMS"
  }
}

run "lifecycle_policy_created" {
  command = plan

  assert {
    condition     = length(aws_ecr_lifecycle_policy.this) == 2
    error_message = "Lifecycle policy should be created for each repository"
  }
}

run "force_delete_disabled_by_default" {
  command = plan

  assert {
    condition     = aws_ecr_repository.this["app-api"].force_delete == false
    error_message = "Force delete should be disabled by default"
  }
}

run "cross_account_policy_not_created_when_null" {
  command = plan

  variables {
    cross_account_arns = null
  }

  assert {
    condition     = length(aws_ecr_repository_policy.cross_account) == 0
    error_message = "Cross-account policy should not be created when cross_account_arns is null"
  }
}

run "cross_account_policy_created_when_set" {
  command = plan

  variables {
    cross_account_arns = ["arn:aws:iam::111111111111:root"]
  }

  assert {
    condition     = length(aws_ecr_repository_policy.cross_account) == 2
    error_message = "Cross-account policy should be created for each repository"
  }
}

run "max_image_count_default" {
  command = plan

  assert {
    condition     = var.max_image_count == 30
    error_message = "Default max image count should be 30"
  }
}
