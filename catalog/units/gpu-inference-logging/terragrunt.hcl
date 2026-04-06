# ---------------------------------------------------------------------------------------------------------------------
# GPU Inference Logging — Catalog Unit
# ---------------------------------------------------------------------------------------------------------------------
# Deploys the Vector v0.54 + ClickHouse v26.3 logging pipeline for the
# gpu-inference cluster.
#
# Pipeline:
#   - Vector Agent DaemonSet: collects kubernetes_logs + journald, parses and
#     filters GPU-relevant events (NCCL, DCGM, vLLM, CUDA), ships to ClickHouse.
#   - ClickHouse StatefulSet: 3 replicas on gp3 storage with TTL-based retention.
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/project/platform-design/terraform/modules/gpu-inference-logging"
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  environment          = local.account_vars.locals.environment
  aws_region           = local.region_vars.locals.aws_region
  gpu_inference_config = try(local.account_vars.locals.gpu_inference_config, {})
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

    provider "kubernetes" {
      host                   = "${dependency.eks.outputs.cluster_endpoint}"
      cluster_ca_certificate = base64decode("${dependency.eks.outputs.cluster_certificate_authority_data}")
      exec {
        api_version = "client.authentication.k8s.io/v1beta1"
        command     = "aws"
        args        = ["eks", "get-token", "--cluster-name", "${dependency.eks.outputs.cluster_name}"]
      }
    }
  PROVIDERS
}

inputs = {
  vector_version      = try(local.gpu_inference_config.vector_version, "0.54.0")
  clickhouse_version  = try(local.gpu_inference_config.clickhouse_version, "26.3.0")
  clickhouse_replicas = try(local.gpu_inference_config.clickhouse_replicas, 3)
  storage_size        = try(local.gpu_inference_config.logging_storage_size, "500Gi")
  retention_days      = try(local.gpu_inference_config.log_retention_days, 30)

  # Password injected via environment variable or secrets manager in CI/CD
  clickhouse_password = get_env("CLICKHOUSE_PASSWORD", "changeme")

  tags = {
    Environment = local.environment
    ClusterRole = "gpu-inference"
    Component   = "logging"
    ManagedBy   = "terragrunt"
  }
}
