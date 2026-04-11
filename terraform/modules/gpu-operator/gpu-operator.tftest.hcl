mock_provider "helm" {}

variables {
  tags = {
    Environment = "test"
    Team        = "gpu"
    ManagedBy   = "terraform"
  }
}

run "default_chart_version" {
  command = plan

  assert {
    condition     = length(var.chart_version) > 0
    error_message = "Chart version should be defined"
  }
}

run "driver_enabled_by_default" {
  command = plan

  assert {
    condition     = var.driver_enabled == true
    error_message = "GPU driver should be enabled by default"
  }
}

run "dcgm_exporter_enabled_by_default" {
  command = plan

  assert {
    condition     = var.dcgm_exporter_enabled == true
    error_message = "DCGM exporter should be enabled by default"
  }
}
