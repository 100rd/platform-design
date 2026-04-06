# ---------------------------------------------------------------------------------------------------------------------
# GPU Inference DRA DeviceClass Definitions — Catalog Unit
# ---------------------------------------------------------------------------------------------------------------------
# Deploys Kubernetes DeviceClass and ResourceClaimTemplate resources for
# DRA-based GPU allocation on the gpu-inference EKS cluster.
#
# Resources created:
#   DeviceClasses:
#     - nvidia-h100-sxm5     — CEL selector for H100 SXM5 (p5.48xlarge)
#     - nvidia-a100-80gb     — CEL selector for A100 80GB (p4d.24xlarge)
#   ResourceClaimTemplates:
#     - single-gpu-inference     — 1x H100 for inference
#     - full-node-training       — 8x H100 ExactCount for training (NVLink island)
#     - prioritized-gpu-inference — H100 preferred, A100 fallback
#
# Requires: EKS 1.35+ with DRA feature gate enabled (GA in 1.35).
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/project/platform-design/terraform/modules/gpu-inference-dra"
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
  tags = {
    Environment = local.environment
    ClusterRole = "gpu-inference"
    ManagedBy   = "terragrunt"
  }
}
