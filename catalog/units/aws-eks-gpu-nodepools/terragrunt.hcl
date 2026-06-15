# ---------------------------------------------------------------------------------------------------------------------
# aws-eks-gpu-nodepools — Catalog Unit (WS-A — ml-platform)
# ---------------------------------------------------------------------------------------------------------------------
# Karpenter GPU pools (spot / scale-to-zero / consolidation / EFA device-plugin)
# (ADR-0046 D1/D3, ADR-0045 D1/D2). Depends on aws-eks-gpu. Default-OFF (apply-gated).
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/terraform/modules/aws-eks-gpu-nodepools"
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  environment         = local.account_vars.locals.environment
  aws_region          = local.region_vars.locals.aws_region
  gpu_platform_config = try(local.account_vars.locals.gpu_platform_config, {})

  cluster_name = "${local.environment}-${local.aws_region}-aws-eks-gpu"
}

dependency "eks" {
  config_path = "../aws-eks-gpu"

  mock_outputs = {
    cluster_name                       = "mock-cluster"
    cluster_endpoint                   = "https://mock-endpoint.eks.amazonaws.com"
    cluster_certificate_authority_data = ""
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
  enabled            = try(local.gpu_platform_config.enabled, false)
  cluster_name       = dependency.eks.outputs.cluster_name
  node_iam_role_name = try(local.gpu_platform_config.node_iam_role_name, "${local.cluster_name}-node")
  ami_family         = "Bottlerocket"

  additional_node_tags = {
    "platform:owner" = "team-ml-platform"
    "platform:env"   = local.environment
  }
}
