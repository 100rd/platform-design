# ---------------------------------------------------------------------------------------------------------------------
# Cilium WireGuard Encryption + High-Scale Tuning — Catalog Unit
# ---------------------------------------------------------------------------------------------------------------------
# Enables WireGuard transparent encryption on Cilium and applies high-scale
# tuning for 5000-node gpu-inference cluster operation.
#
# Depends on gpu-inference-cilium (Issue #70) for base Cilium deployment.
# Creates encryption config, optional NCCL traffic exemption, and
# Prometheus alerting rules for BGP session and WireGuard monitoring.
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/project/platform-design/terraform/modules/gpu-inference-cilium-encryption"
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
  operator_replicas = 3
  k8s_api_qps       = 50
  k8s_api_burst     = 100

  agent_cpu_limit      = "2"
  agent_memory_limit   = "2Gi"
  agent_cpu_request    = "500m"
  agent_memory_request = "512Mi"

  exclude_nccl_from_encryption = try(local.gpu_inference_config.exclude_nccl_encryption, false)
  enable_prometheus_alerts     = true

  tags = {
    Environment = local.environment
    ClusterRole = "gpu-inference"
    ManagedBy   = "terragrunt"
  }
}
