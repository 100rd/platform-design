mock_provider "aws" {}

variables {
  kms_key_arn = "arn:aws:kms:eu-west-1:111111111111:key/00000000-0000-0000-0000-000000000000"
  tags = {
    Environment = "shared"
    Team        = "platform"
    ManagedBy   = "terraform"
  }
}

run "creates_a_rule_per_upstream" {
  command = plan

  assert {
    condition     = length(aws_ecr_pull_through_cache_rule.this) == length(var.upstreams)
    error_message = "Should create one pull-through cache rule per upstream"
  }
}

run "default_upstreams_present" {
  command = plan

  assert {
    condition     = aws_ecr_pull_through_cache_rule.this["ecr-public"].upstream_registry_url == "public.ecr.aws"
    error_message = "ecr-public upstream should map to public.ecr.aws"
  }

  assert {
    condition     = aws_ecr_pull_through_cache_rule.this["k8s"].upstream_registry_url == "registry.k8s.io"
    error_message = "k8s upstream should map to registry.k8s.io"
  }

  assert {
    condition     = aws_ecr_pull_through_cache_rule.this["quay"].upstream_registry_url == "quay.io"
    error_message = "quay upstream should map to quay.io"
  }

  assert {
    condition     = aws_ecr_pull_through_cache_rule.this["ghcr"].upstream_registry_url == "ghcr.io"
    error_message = "ghcr upstream should map to ghcr.io"
  }
}

run "dockerhub_credential_secret_created_with_required_prefix" {
  command = plan

  assert {
    condition     = aws_secretsmanager_secret.dockerhub["docker-hub"].name == "ecr-pullthroughcache/docker-hub"
    error_message = "Docker Hub credential secret name must start with the AWS-required ecr-pullthroughcache/ prefix"
  }

  assert {
    condition     = length(aws_secretsmanager_secret.dockerhub) == 1
    error_message = "Only Docker Hub (requires_credential = true) should get an upstream credential secret by default"
  }
}

run "repository_creation_template_uses_kms_and_role" {
  command = plan

  assert {
    condition     = length(aws_ecr_repository_creation_template.this) == 1
    error_message = "Repository creation template should be created by default"
  }

  assert {
    condition     = contains(aws_ecr_repository_creation_template.this[0].applied_for, "PULL_THROUGH_CACHE")
    error_message = "Repository creation template must be applied for PULL_THROUGH_CACHE"
  }

  assert {
    condition     = aws_ecr_repository_creation_template.this[0].encryption_configuration[0].encryption_type == "KMS"
    error_message = "Cached repositories should be KMS-encrypted when a kms_key_arn is provided"
  }

  assert {
    condition     = length(aws_iam_role.template) == 1
    error_message = "A custom IAM role is required for KMS-encrypted / tagged cached repositories"
  }
}

run "immutable_tags_by_default" {
  command = plan

  assert {
    condition     = aws_ecr_repository_creation_template.this[0].image_tag_mutability == "IMMUTABLE"
    error_message = "Cached repositories should use immutable image tags by default"
  }
}

run "scanning_configuration_managed_by_default" {
  command = plan

  assert {
    condition     = length(aws_ecr_registry_scanning_configuration.this) == 1
    error_message = "Registry scanning configuration should be managed by default"
  }

  assert {
    condition     = aws_ecr_registry_scanning_configuration.this[0].scan_type == "ENHANCED"
    error_message = "Default scan_type should be ENHANCED"
  }
}

run "rejects_unsupported_upstream" {
  command = plan

  variables {
    upstreams = {
      bogus = {
        upstream_registry_url = "registry.example.com"
      }
    }
  }

  expect_failures = [
    var.upstreams,
  ]
}
