# ---------------------------------------------------------------------------------------------------------------------
# Minimal Platform Cilium CNI — Catalog Unit
# ---------------------------------------------------------------------------------------------------------------------
# Deploys Cilium as the CNI for the minimal-platform EKS cluster.
# Must be deployed AFTER minimal-platform-eks.
#
# Key differences from the standard cilium catalog unit:
#   - enable_clustermesh = false (Decision 3: this stack is standalone, not part
#     of the multi-region mesh; saves ClusterMesh API server cost)
#   - cluster_name derived from dependency.eks.outputs.cluster_name (not hardcoded)
#   - cluster_oidc_issuer_url + cluster_oidc_provider_arn wired for IRSA
#     (Cilium operator needs EC2 ENI APIs; IRSA role created by the module)
#   - generate "k8s_providers" block for helm + kubernetes providers
#   - Extended mock_outputs covering cluster_certificate_authority_data,
#     cluster_name, cluster_oidc_issuer_url, and oidc_provider_arn
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
# DEPENDENCY: Minimal Platform EKS Cluster
# ---------------------------------------------------------------------------------------------------------------------

dependency "eks" {
  config_path = "../eks"

  mock_outputs = {
    cluster_endpoint                   = "https://XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX.gr7.eu-central-1.eks.amazonaws.com"
    cluster_certificate_authority_data = "bW9jay1jYS1kYXRh"
    cluster_name                       = "staging-eu-central-1-minimal-platform"
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

  # Default deny policy — PCI-DSS Req 1.2
  enable_default_deny = true

  # WireGuard transparent encryption — PCI-DSS Req 4.1
  enable_encryption = true
  encryption_type   = "wireguard"

  # HA for operator
  operator_replicas = local.environment == "prod" ? 2 : 1

  # Decision 3: ClusterMesh disabled — this stack is standalone and does not
  # participate in the multi-region service mesh.
  enable_clustermesh             = false
  cluster_mesh_name              = ""
  cluster_mesh_id                = 0
  clustermesh_apiserver_replicas = 2

  tags = {
    Environment = local.environment
    ManagedBy   = "terragrunt"
  }
}
