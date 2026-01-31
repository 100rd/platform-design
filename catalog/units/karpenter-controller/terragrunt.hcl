# ---------------------------------------------------------------------------------------------------------------------
# Karpenter Controller — Catalog Unit
# ---------------------------------------------------------------------------------------------------------------------
# Deploys the Karpenter Helm chart (controller) using the custom Terraform module.
# Depends on EKS cluster and Karpenter IAM resources.
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/project/platform-design/terraform/modules/karpenter"
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  account_name = local.account_vars.locals.account_name
  aws_region   = local.region_vars.locals.aws_region
  environment  = local.account_vars.locals.environment
}

# ---------------------------------------------------------------------------------------------------------------------
# DEPENDENCIES
# ---------------------------------------------------------------------------------------------------------------------

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

dependency "karpenter_iam" {
  config_path = "../karpenter-iam"

  mock_outputs = {
    iam_role_arn          = "arn:aws:iam::123456789012:role/mock-karpenter-role"
    queue_name            = "mock-karpenter-queue"
    node_iam_role_name    = "mock-karpenter-node-role"
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

# ---------------------------------------------------------------------------------------------------------------------
# Kubernetes / Helm providers + aws.virginia alias for ECR public token
# ---------------------------------------------------------------------------------------------------------------------

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

    provider "aws" {
      alias  = "virginia"
      region = "us-east-1"
    }
  PROVIDERS
}

# ---------------------------------------------------------------------------------------------------------------------
# MODULE INPUTS
# ---------------------------------------------------------------------------------------------------------------------

inputs = {
  cluster_name     = dependency.eks.outputs.cluster_name
  cluster_endpoint = dependency.eks.outputs.cluster_endpoint

  karpenter_controller_role_arn       = dependency.karpenter_iam.outputs.iam_role_arn
  karpenter_interruption_queue_name   = dependency.karpenter_iam.outputs.queue_name
  karpenter_node_iam_role_name        = dependency.karpenter_iam.outputs.node_iam_role_name

  controller_replicas = try(local.account_vars.locals.karpenter_controller_replicas, 2)
  log_level           = try(local.account_vars.locals.karpenter_log_level, "info")

  tags = {
    Environment = local.environment
    ManagedBy   = "terragrunt"
  }
}
