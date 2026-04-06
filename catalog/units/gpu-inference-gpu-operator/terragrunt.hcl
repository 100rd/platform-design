# ---------------------------------------------------------------------------------------------------------------------
# NVIDIA GPU Operator v26.3 — Catalog Unit
# ---------------------------------------------------------------------------------------------------------------------
# Deploys NVIDIA GPU Operator with DRA driver on the gpu-inference cluster.
# DRA replaces the traditional device-plugin, publishing GPU attributes via
# ResourceSlice objects for topology-aware scheduling.
#
# Components deployed: DRA Driver, Container Toolkit, GPU Feature Discovery,
# Node Feature Discovery, CDI. NVIDIA driver is pre-installed in Bottlerocket AMI.
# DCGM Exporter deployed separately (Phase 5, Issue #77).
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/project/platform-design/terraform/modules/gpu-operator"
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  environment = local.account_vars.locals.environment
  aws_region  = local.region_vars.locals.aws_region
}

dependency "eks" {
  config_path = "../gpu-inference-eks"

  mock_outputs = {
    cluster_name                       = "mock-cluster"
    cluster_endpoint                   = "https://mock-endpoint.eks.amazonaws.com"
    cluster_certificate_authority_data = "bW9jay1jZXJ0LWRhdGE="
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

generate "k8s_providers" {
  path      = "k8s_providers_override.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-PROVIDERS
    provider "helm" {
      kubernetes {
        host                   = "${dependency.eks.outputs.cluster_endpoint}"
        cluster_ca_certificate = base64decode("${dependency.eks.outputs.cluster_certificate_authority_data}")
        exec {
          api_version = "client.authentication.k8s.io/v1beta1"
          command     = "aws"
          args        = ["eks", "get-token", "--cluster-name", "${dependency.eks.outputs.cluster_name}"]
        }
      }
    }
  PROVIDERS
}

inputs = {
  chart_version         = "v26.3.0"
  dra_driver_version    = "v25.3.0"
  driver_enabled        = false
  dcgm_exporter_enabled = false

  operator_cpu_limit    = "500m"
  operator_memory_limit = "512Mi"

  tags = {
    Environment = local.environment
    ClusterRole = "gpu-inference"
    ManagedBy   = "terragrunt"
  }
}
