# ---------------------------------------------------------------------------------------------------------------------
# ArgoCD v3.3 — GPU Inference Fleet Management Catalog Unit
# ---------------------------------------------------------------------------------------------------------------------
# Configures ArgoCD v3.3 on the Hub (platform) cluster with ApplicationSets
# and RBAC for gpu-inference project isolation.
#
# Uses the existing ArgoCD installation from the platform stack,
# extended with gpu-inference-specific AppProjects and ApplicationSets.
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/project/platform-design/terraform/modules/gpu-inference-argocd"
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  environment = local.account_vars.locals.environment
  aws_region  = local.region_vars.locals.aws_region
}

dependency "eks" {
  config_path = "../eks"

  mock_outputs = {
    cluster_name                       = "mock-cluster"
    cluster_endpoint                   = "https://mock-endpoint.eks.amazonaws.com"
    cluster_certificate_authority_data = "bW9jay1jZXJ0LWRhdGE="
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

dependency "argocd" {
  config_path = "../argocd"

  mock_outputs = {
    namespace = "argocd"
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
  argocd_namespace = dependency.argocd.outputs.namespace

  gpu_inference_repo_url  = try(local.account_vars.locals.gpu_inference_repo_url, "https://github.com/100rd/platform-design.git")
  gpu_inference_repo_path = "argocd/gpu-inference"

  tags = {
    Environment = local.environment
    ManagedBy   = "terragrunt"
  }
}
