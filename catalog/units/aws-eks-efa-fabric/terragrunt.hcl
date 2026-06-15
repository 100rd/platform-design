# ---------------------------------------------------------------------------------------------------------------------
# aws-eks-efa-fabric — Catalog Unit (WS-A — ml-platform)
# ---------------------------------------------------------------------------------------------------------------------
# EFA exposure (ADR-0045 D2/D3/D4). Mode is DERIVED from the provisioner: device-plugin
# under Karpenter (default), dra only on managed node groups. The stack sets this, never
# set independently. Depends on aws-eks-gpu. Default-OFF (apply-gated).
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/terraform/modules/aws-eks-efa-fabric"
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  environment         = local.account_vars.locals.environment
  gpu_platform_config = try(local.account_vars.locals.gpu_platform_config, {})

  # mode derived from provisioner (ADR-0045 D2/D3) — default Karpenter → device-plugin.
  provisioner = try(local.gpu_platform_config.efa_provisioner, "karpenter")
  efa_mode    = local.provisioner == "managed-node-group" ? "dra" : "device-plugin"
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
  enabled      = try(local.gpu_platform_config.enabled, false)
  cluster_name = dependency.eks.outputs.cluster_name
  mode         = local.efa_mode
  provisioner  = local.provisioner

  platform_labels = {
    "platform.env"   = local.environment
    "platform.owner" = "team-ml-platform"
  }
}
