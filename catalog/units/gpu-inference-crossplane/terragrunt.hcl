# ---------------------------------------------------------------------------------------------------------------------
# Crossplane v2.2 — GPU Inference Hub Catalog Unit
# ---------------------------------------------------------------------------------------------------------------------
# Deploys Crossplane v2.2 with provider-family-aws on the Hub (platform) cluster
# to manage the gpu-inference fleet via Hub-and-Spoke model.
#
# Crossplane handles dynamic GPU node management at scale (5000 nodes) where
# individual Terraform resources would cause tfstate explosion.
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/project/platform-design/terraform/modules/crossplane"
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
  chart_version        = "2.2.0"
  provider_aws_version = "2.5.0"

  crossplane_memory_limit = local.environment == "prod" ? "4Gi" : "2Gi"
  crossplane_cpu_limit    = local.environment == "prod" ? "2" : "1"

  tags = {
    Environment = local.environment
    ManagedBy   = "terragrunt"
  }
}
