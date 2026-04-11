mock_provider "aws" {}

variables {
  vpc_id = "vpc-12345678"
  tags = {
    Environment = "test"
    Team        = "network"
    ManagedBy   = "terraform"
  }
}

run "empty_subnet_ids_by_default" {
  command = plan

  assert {
    condition     = length(var.subnet_ids) == 0
    error_message = "No subnet IDs should be defined by default"
  }
}

run "empty_security_groups_by_default" {
  command = plan

  assert {
    condition     = length(var.security_group_ids) == 0
    error_message = "No security group IDs should be defined by default"
  }
}

run "empty_route_tables_by_default" {
  command = plan

  assert {
    condition     = length(var.route_table_ids) == 0
    error_message = "No route table IDs should be defined by default"
  }
}
