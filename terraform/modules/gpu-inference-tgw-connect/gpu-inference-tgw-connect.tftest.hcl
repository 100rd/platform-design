mock_provider "aws" {}

variables {
  name                     = "test-tgw-connect"
  transit_gateway_id       = "tgw-12345"
  transit_gateway_attachment_id = "tgw-attach-12345"
  tags = {
    Environment = "test"
    Team        = "gpu"
    ManagedBy   = "terraform"
  }
}

run "module_initializes" {
  command = plan

  assert {
    condition     = true
    error_message = "Module should initialize without errors"
  }
}
