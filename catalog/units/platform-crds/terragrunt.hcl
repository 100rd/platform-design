# ---------------------------------------------------------------------------------------------------------------------
# Platform CRDs — Catalog Unit
# ---------------------------------------------------------------------------------------------------------------------
# Deploys all platform CRDs into the EKS cluster before ArgoCD or any operator is installed.
# Terraform is the single owner of CRDs; ArgoCD only deploys operators and workloads.
#
# Depends on: eks
# Depended on by: argocd, monitoring
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/project/platform-design/terraform/modules/platform-crds"
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  account_name = local.account_vars.locals.account_name
  aws_region   = local.region_vars.locals.aws_region
  environment  = local.account_vars.locals.environment
}

# ---------------------------------------------------------------------------------------------------------------------
# DEPENDENCY: EKS
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

# ---------------------------------------------------------------------------------------------------------------------
# Kubernetes / Helm / kubectl providers
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

    provider "kubectl" {
      host                   = "${dependency.eks.outputs.cluster_endpoint}"
      cluster_ca_certificate = base64decode("${dependency.eks.outputs.cluster_certificate_authority_data}")
      load_config_file       = false
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
  # CRD versions — override from account.hcl or use module defaults
  argocd_version                  = try(local.account_vars.locals.argocd_version, null)
  cert_manager_version            = try(local.account_vars.locals.cert_manager_version, null)
  external_secrets_version        = try(local.account_vars.locals.external_secrets_version, null)
  prometheus_operator_crds_version = try(local.account_vars.locals.prometheus_operator_crds_version, null)
  gatekeeper_version              = try(local.account_vars.locals.gatekeeper_version, null)
  velero_version                  = try(local.account_vars.locals.velero_version, null)
  kargo_version                   = try(local.account_vars.locals.kargo_version, null)

  tags = {
    Environment = local.environment
    ManagedBy   = "terragrunt"
  }
}
