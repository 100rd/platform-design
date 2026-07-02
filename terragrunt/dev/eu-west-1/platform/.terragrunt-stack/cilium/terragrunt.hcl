# ---------------------------------------------------------------------------------------------------------------------
# Cilium CNI — Catalog Unit
# ---------------------------------------------------------------------------------------------------------------------
# Deploys Cilium as the CNI for EKS, replacing AWS VPC CNI.
# Must be deployed AFTER EKS but BEFORE Karpenter nodepools.
#
# Prerequisites:
#   - EKS cluster created with cluster_addons.vpc-cni DISABLED
#   - Karpenter EC2NodeClass using Bottlerocket AMI family
#   - IRSA enabled on the EKS cluster (enable_irsa = true)
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/terraform/modules/cilium"
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  environment = local.account_vars.locals.environment
  aws_region  = local.region_vars.locals.aws_region
}

# ---------------------------------------------------------------------------------------------------------------------
# DEPENDENCY: EKS Cluster
# ---------------------------------------------------------------------------------------------------------------------

dependency "eks" {
  config_path = "../eks"

  mock_outputs = {
    cluster_endpoint                   = "https://XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX.gr7.eu-central-1.eks.amazonaws.com"
    cluster_certificate_authority_data = "bW9jay1jYS1kYXRh"
    cluster_name                       = "staging-eu-central-1-platform"
    cluster_oidc_issuer_url            = "https://oidc.eks.eu-central-1.amazonaws.com/id/MOCKMOCKMOCKMOCKMOCKMOCKMOCKMOCK"
    oidc_provider_arn                  = "arn:aws:iam::000000000000:oidc-provider/oidc.eks.eu-central-1.amazonaws.com/id/MOCKMOCKMOCKMOCKMOCKMOCKMOCKMOCK"
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

# ---------------------------------------------------------------------------------------------------------------------
# Kubernetes / Helm providers for Cilium deployment
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
  PROVIDERS
}

# ---------------------------------------------------------------------------------------------------------------------
# MODULE INPUTS
# ---------------------------------------------------------------------------------------------------------------------

inputs = {
  # Identity — required for IRSA role naming and OIDC trust policy
  cluster_name              = dependency.eks.outputs.cluster_name
  cluster_oidc_issuer_url   = dependency.eks.outputs.cluster_oidc_issuer_url
  cluster_oidc_provider_arn = dependency.eks.outputs.oidc_provider_arn

  cluster_endpoint = replace(dependency.eks.outputs.cluster_endpoint, "https://", "")

  cilium_version = "1.16.5"

  # Start with kube-proxy enabled for safer migration
  # Set to true after validating Cilium is stable
  replace_kube_proxy = local.account_vars.locals.cilium_replace_kube_proxy

  # Hubble observability
  enable_hubble    = true
  enable_hubble_ui = true

  # Prometheus integration
  enable_service_monitor = true

  # ENI prefix delegation for higher pod density
  enable_prefix_delegation = true

  # Bandwidth manager for QoS
  enable_bandwidth_manager = true

  # Default deny policy — PCI-DSS Req 1.2 (restrict CDE connections)
  enable_default_deny = true

  # WireGuard transparent encryption — PCI-DSS Req 4.1 (encrypt data in transit)
  enable_encryption = true
  encryption_type   = "wireguard"

  # HA for operator
  operator_replicas = local.environment == "prod" ? 2 : 1

  # ClusterMesh for multi-region service discovery
  enable_clustermesh             = try(local.account_vars.locals.enable_clustermesh, false)
  cluster_mesh_name              = try(local.account_vars.locals.enable_clustermesh, false) ? "${local.environment}-${local.region_vars.locals.region_short}" : ""
  cluster_mesh_id                = try(local.account_vars.locals.enable_clustermesh, false) ? local.account_vars.locals.clustermesh_cluster_ids[local.aws_region] : 0
  clustermesh_apiserver_replicas = try(local.account_vars.locals.clustermesh_apiserver_replicas, 2)

  tags = {
    Environment = local.environment
    ManagedBy   = "terragrunt"
  }
}
