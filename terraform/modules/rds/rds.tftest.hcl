# NOTE: The RDS module wraps terraform-aws-modules/rds/aws and
# terraform-aws-modules/security-group/aws which create IAM roles with
# assume_role_policy that mock_provider generates as invalid JSON.
# Tests are limited to variable-default validation and the custom parameter group.

mock_provider "aws" {}

variables {
  identifier           = "test-db"
  vpc_id               = "vpc-12345678"
  subnet_ids           = ["subnet-aaa", "subnet-bbb"]
  db_subnet_group_name = "test-subnet-group"
  password             = "test-password-123!"
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

run "multi_az_enabled_by_default" {
  command = plan

  assert {
    condition     = var.multi_az == true
    error_message = "Multi-AZ should be enabled by default"
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

run "default_environment_dev" {
  command = plan

  assert {
    condition     = var.environment == "dev"
    error_message = "Default environment should be dev"
  }
}

run "default_db_name" {
  command = plan

  assert {
    condition     = var.db_name == "dns_failover"
    error_message = "Default database name should be dns_failover"
  }
}
