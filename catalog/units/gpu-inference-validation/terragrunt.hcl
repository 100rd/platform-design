# ---------------------------------------------------------------------------------------------------------------------
# GPU Inference Validation Suite — Catalog Unit
# ---------------------------------------------------------------------------------------------------------------------
# Deploys the Definition-of-Done validation suite for the gpu-inference cluster.
#
# Provisions:
#   - Namespace gpu-inference-validation
#   - ServiceAccount + ClusterRole with cluster-reader permissions
#   - ConfigMap containing all test manifests (network latency, NCCL, DRA, gang,
#     observability, security, vLLM benchmark)
#   - CronJob to run the full suite weekly (Sunday 02:00 UTC)
#
# Depends on:
#   - gpu-inference-eks  (kubernetes provider endpoint + credentials)
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/terraform/modules/gpu-inference-validation"
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  environment  = local.account_vars.locals.environment
  aws_region   = local.region_vars.locals.aws_region
  cluster_name = "${local.environment}-${local.aws_region}-gpu-inference"
}

# ---------------------------------------------------------------------------------------------------------------------
# DEPENDENCY: GPU Inference EKS — supplies cluster endpoint and CA data
# ---------------------------------------------------------------------------------------------------------------------

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

# ---------------------------------------------------------------------------------------------------------------------
# PROVIDER: Kubernetes — connects to the gpu-inference EKS cluster
# ---------------------------------------------------------------------------------------------------------------------

generate "k8s_provider" {
  path      = "k8s_provider_override.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-PROVIDERS
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

# ---------------------------------------------------------------------------------------------------------------------
# MODULE INPUTS
# ---------------------------------------------------------------------------------------------------------------------

inputs = {
  cluster_name = local.cluster_name
  namespace    = "gpu-inference-validation"

  # Weekly on Sunday at 02:00 UTC — runs during low-traffic maintenance window
  schedule = "0 2 * * 0"

  # Service endpoints (must be reachable from within the cluster)
  vllm_server_url      = "http://vllm-server.gpu-inference.svc.cluster.local:8000"
  victoria_metrics_url = "http://victoria-metrics.monitoring.svc.cluster.local:8428"
  clickhouse_host      = "clickhouse.logging.svc.cluster.local"

  # Path to test manifests relative to the Terraform working directory.
  # At plan/apply time Terragrunt runs from the catalog unit directory; the
  # relative path resolves to tests/gpu-inference/ in the repo root.
  test_manifests_path = "${get_repo_root()}/tests/gpu-inference"

  tags = {
    Environment = local.environment
    ClusterRole = "gpu-inference"
    Component   = "validation-suite"
    ManagedBy   = "terragrunt"
  }
}
