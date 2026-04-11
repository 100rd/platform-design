mock_provider "google" {}

variables {
  project_id = "test-gcp-project"
  region     = "us-central1"
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
