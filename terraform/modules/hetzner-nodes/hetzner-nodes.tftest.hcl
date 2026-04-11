mock_provider "hcloud" {}

variables {
  name_prefix = "test-node"
}

run "default_node_count" {
  command = plan

  assert {
    condition     = var.node_count == 1
    error_message = "Default node count should be 1"
  }
}

run "default_server_type" {
  command = plan

  assert {
    condition     = var.server_type == "cx31"
    error_message = "Default server type should be cx31"
  }
}

run "default_image" {
  command = plan

  assert {
    condition     = var.image == "ubuntu-22.04"
    error_message = "Default image should be ubuntu-22.04"
  }
}

run "default_location" {
  command = plan

  assert {
    condition     = var.location == "fsn1"
    error_message = "Default location should be fsn1"
  }
}
