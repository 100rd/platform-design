mock_provider "aws" {}

variables {
  identifier = "test-db"
  vpc_id     = "vpc-12345678"
  subnet_ids = ["subnet-aaa", "subnet-bbb"]
  db_subnet_group_name = "test-subnet-group"
  password   = "test-password-123!"
  tags = {
    Environment = "test"
    Team        = "platform"
    ManagedBy   = "terraform"
  }
}

run "creates_ssl_parameter_group" {
  command = plan

  assert {
    condition     = aws_db_parameter_group.this.family == "postgres17"
    error_message = "Parameter group should use postgres17 family"
  }

  assert {
    condition     = aws_db_parameter_group.this.name == "test-db-pg17-ssl"
    error_message = "Parameter group name should include identifier"
  }
}

run "storage_encrypted_by_default" {
  command = plan

  assert {
    condition     = module.db.storage_encrypted == true
    error_message = "Storage encryption should be enabled for PCI-DSS Req 3.4"
  }
}

run "multi_az_enabled_by_default" {
  command = plan

  assert {
    condition     = var.multi_az == true
    error_message = "Multi-AZ should be enabled by default"
  }
}

run "performance_insights_enabled" {
  command = plan

  assert {
    condition     = module.db.performance_insights_enabled == true
    error_message = "Performance Insights should be enabled"
  }
}

run "cloudwatch_logs_exported" {
  command = plan

  assert {
    condition     = length(module.db.enabled_cloudwatch_logs_exports) == 2
    error_message = "PostgreSQL and upgrade logs should be exported to CloudWatch"
  }
}

run "skip_final_snapshot_false_in_prod" {
  command = plan

  variables {
    environment = "prod"
  }

  assert {
    condition     = module.db.skip_final_snapshot == false
    error_message = "Final snapshot should not be skipped in production"
  }
}

run "skip_final_snapshot_true_in_dev" {
  command = plan

  variables {
    environment = "dev"
  }

  assert {
    condition     = module.db.skip_final_snapshot == true
    error_message = "Final snapshot can be skipped in dev"
  }
}

run "security_group_created" {
  command = plan

  assert {
    condition     = module.security_group.name == "test-db-sg"
    error_message = "Security group name should include identifier"
  }
}

run "default_instance_class" {
  command = plan

  assert {
    condition     = var.instance_class == "db.t3.small"
    error_message = "Default instance class should be db.t3.small"
  }
}

run "default_allocated_storage" {
  command = plan

  assert {
    condition     = var.allocated_storage == 20
    error_message = "Default allocated storage should be 20 GB"
  }
}
