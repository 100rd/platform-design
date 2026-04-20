mock_provider "kubernetes" {}

variables {}

run "no_connections_by_default" {
  command = plan

  assert {
    condition     = length(var.remote_clusters) == 0
    error_message = "No remote clusters should be connected by default"
  }
}
