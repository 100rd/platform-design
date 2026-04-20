mock_provider "helm" {}

variables {
  tags = {
    Environment = "test"
    Team        = "platform"
    ManagedBy   = "terraform"
  }
}

run "default_chart_version" {
  command = plan

  assert {
    condition     = var.chart_version == "2.2.0"
    error_message = "Default Crossplane chart version should be 2.2.0"
  }
}

run "default_provider_aws_version" {
  command = plan

  assert {
    condition     = var.provider_aws_version == "2.5.0"
    error_message = "Default AWS provider version should be 2.5.0"
  }
}

run "default_resource_limits" {
  command = plan

  assert {
    condition     = var.crossplane_memory_limit == "2Gi"
    error_message = "Default memory limit should be 2Gi"
  }

  assert {
    condition     = var.crossplane_cpu_limit == "1"
    error_message = "Default CPU limit should be 1"
  }
}
