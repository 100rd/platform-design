# ---------------------------------------------------------------------------------------------------------------------
# GPU Inference Scheduling Policies — Catalog Unit
# ---------------------------------------------------------------------------------------------------------------------
# Deploys Kubernetes scheduling primitives for the gpu-inference cluster:
#   - Four PriorityClasses (system-critical / training-high / inference-medium / batch-low)
#   - Volcano PodGroup example for 8-pod gang scheduling
#   - Per-namespace ResourceQuotas for GPU/CPU/memory limits
#
# Depends on: gpu-inference-eks (provides cluster endpoint + CA data)
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/project/platform-design/terraform/modules/gpu-inference-scheduling-policies"
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
  # Priority values — override in account.hcl gpu_inference_config if needed
  training_priority  = try(local.gpu_inference_config.training_priority, 100000)
  inference_priority = try(local.gpu_inference_config.inference_priority, 50000)
  batch_priority     = try(local.gpu_inference_config.batch_priority, 10000)

  # ResourceQuotas enabled by default; disable in dev via gpu_inference_config
  enable_resource_quotas = try(local.gpu_inference_config.enable_resource_quotas, true)

  tags = {
    Environment = local.environment
    ClusterRole = "gpu-inference"
    ManagedBy   = "terragrunt"
  }
}
