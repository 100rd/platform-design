# ---------------------------------------------------------------------------------------------------------------------
# GKE GPU DCGM Exporter — Catalog Unit (WS-A — ml-infra)
# ---------------------------------------------------------------------------------------------------------------------
# Installs the NVIDIA DCGM exporter DaemonSet on the GPU analysis GKE cluster, exposing
# GPU metrics on :9400 with a ServiceMonitor so VictoriaMetrics scrapes them.
#
# Dependencies: gcp-gpu-gke
# Requires project.hcl with: project_id, environment, gpu_analysis_config
# Requires region.hcl with: gcp_region
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/terraform/modules/gke-gpu-dcgm"
}

locals {
  project_vars = read_terragrunt_config(find_in_parent_folders("project.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  gcp_project_id      = local.project_vars.locals.project_id
  environment         = local.project_vars.locals.environment
  gcp_region          = local.region_vars.locals.gcp_region
  gpu_analysis_config = try(local.project_vars.locals.gpu_analysis_config, {})
}

dependency "gke" {
  config_path = "../gcp-gpu-gke"

  mock_outputs = {
    name           = "mock-cluster"
    endpoint       = "10.0.0.1"
    ca_certificate = "bW9jay1jZXJ0LWRhdGE="
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

generate "gke_providers" {
  path      = "gke_providers_override.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-PROVIDERS
    data "google_client_config" "this" {}

    provider "helm" {
      kubernetes {
        host                   = "https://${dependency.gke.outputs.endpoint}"
        token                  = data.google_client_config.this.access_token
        cluster_ca_certificate = base64decode("${dependency.gke.outputs.ca_certificate}")
      }
    }

    provider "kubernetes" {
      host                   = "https://${dependency.gke.outputs.endpoint}"
      token                  = data.google_client_config.this.access_token
      cluster_ca_certificate = base64decode("${dependency.gke.outputs.ca_certificate}")
    }
  PROVIDERS
}

inputs = {
  enabled       = try(local.gpu_analysis_config.dcgm_enabled, true)
  chart_version = try(local.gpu_analysis_config.dcgm_chart_version, "3.6.1")

  gpu_node_selector = {
    "cloud.google.com/gke-accelerator" = try(local.gpu_analysis_config.gpu_accelerator_type, "nvidia-l4")
  }

  # VictoriaMetrics is the metrics backend; its operator selects on this release label.
  service_monitor_release_label = "victoria-metrics"
  scrape_interval               = "15s"

  platform_labels = {
    "platform.env"   = local.environment
    "platform.owner" = "team-data"
  }
}
