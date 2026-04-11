mock_provider "aws" {}

variables {
  name = "test-accelerator"
  listeners = [{
    port_ranges = [{ from_port = 443, to_port = 443 }]
    protocol    = "TCP"
  }]
  endpoint_groups = {}
  tags = {
    Environment = "test"
    Team        = "network"
    ManagedBy   = "terraform"
  }
}

run "enabled_by_default" {
  command = plan

  assert {
    condition     = var.enabled == true
    error_message = "Global Accelerator should be enabled by default"
  }
}

run "creates_accelerator_when_enabled" {
  command = plan

  assert {
    condition     = length(aws_globalaccelerator_accelerator.this) == 1
    error_message = "Accelerator should be created when enabled"
  }
}

run "skips_accelerator_when_disabled" {
  command = plan

  variables {
    enabled = false
  }

  assert {
    condition     = length(aws_globalaccelerator_accelerator.this) == 0
    error_message = "Accelerator should not be created when disabled"
  }
}

run "default_ipv4_address_type" {
  command = plan

  assert {
    condition     = var.ip_address_type == "IPV4"
    error_message = "Default IP address type should be IPV4"
  }
}

run "flow_logs_enabled_by_default" {
  command = plan

  assert {
    condition     = var.flow_logs_enabled == true
    error_message = "Flow logs should be enabled by default"
  }
}
