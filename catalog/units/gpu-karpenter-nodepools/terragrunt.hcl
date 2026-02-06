# ---------------------------------------------------------------------------------------------------------------------
# GPU Analysis Karpenter NodePools — Catalog Unit
# ---------------------------------------------------------------------------------------------------------------------
# Deploys Karpenter NodePool and EC2NodeClass CRDs for GPU video analysis workloads.
# Uses the extended karpenter-nodepools module with HPC fields (placement groups,
# AZ pinning, block device overrides).
#
# Dependencies: gpu-eks, gpu-karpenter-iam, gpu-karpenter-controller,
#               gpu-cilium, gpu-placement-group
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/project/platform-design/terraform/modules/karpenter-nodepools"
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  account_name         = local.account_vars.locals.account_name
  aws_region           = local.region_vars.locals.aws_region
  environment          = local.account_vars.locals.environment
  gpu_analysis_config  = local.account_vars.locals.gpu_analysis_config
}

# ---------------------------------------------------------------------------------------------------------------------
# DEPENDENCIES
# ---------------------------------------------------------------------------------------------------------------------

dependency "eks" {
  config_path = "../gpu-eks"

  mock_outputs = {
    cluster_name                       = "mock-gpu-analysis-cluster"
    cluster_endpoint                   = "https://mock-endpoint.eks.amazonaws.com"
    cluster_certificate_authority_data = "bW9jay1jZXJ0LWRhdGE="
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

dependency "karpenter_iam" {
  config_path = "../gpu-karpenter-iam"

  mock_outputs = {
    node_iam_role_name = "mock-gpu-analysis-karpenter-node-role"
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

dependency "karpenter_controller" {
  config_path = "../gpu-karpenter-controller"

  mock_outputs = {
    release_name = "karpenter"
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

dependency "cilium" {
  config_path = "../gpu-cilium"

  mock_outputs = {
    cilium_version = "1.16.5"
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

dependency "placement_group" {
  config_path = "../gpu-placement-group"

  mock_outputs = {
    placement_group_names = { gpu-cluster = "mock-placement-group" }
    placement_group_ids   = { gpu-cluster = "pg-00000000000000000" }
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

# ---------------------------------------------------------------------------------------------------------------------
# Kubernetes provider
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
  cluster_name       = dependency.eks.outputs.cluster_name
  node_iam_role_name = dependency.karpenter_iam.outputs.node_iam_role_name
  nodepool_configs   = try(local.gpu_analysis_config.karpenter_nodepools, {})

  # Use Bottlerocket for Cilium CNI
  ami_family = try(local.gpu_analysis_config.karpenter_ami_family, "Bottlerocket")
}
