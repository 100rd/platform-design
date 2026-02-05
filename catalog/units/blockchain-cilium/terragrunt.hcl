# ---------------------------------------------------------------------------------------------------------------------
# Blockchain Cilium CNI — Catalog Unit
# ---------------------------------------------------------------------------------------------------------------------
# Deploys Cilium as the CNI for the blockchain EKS cluster.
# Must be deployed AFTER blockchain-eks but BEFORE blockchain-karpenter-nodepools.
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/project/platform-design/terraform/modules/cilium"
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  environment       = local.account_vars.locals.environment
  aws_region        = local.region_vars.locals.aws_region
  blockchain_config = local.account_vars.locals.blockchain_config
  cluster_name      = "${local.environment}-${local.aws_region}-blockchain"
}

# ---------------------------------------------------------------------------------------------------------------------
# DEPENDENCY: Blockchain EKS Cluster
# ---------------------------------------------------------------------------------------------------------------------

dependency "eks" {
  config_path = "../blockchain-eks"

  mock_outputs = {
    cluster_endpoint = "https://XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX.gr7.eu-central-1.eks.amazonaws.com"
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

# ---------------------------------------------------------------------------------------------------------------------
# MODULE INPUTS
# ---------------------------------------------------------------------------------------------------------------------

inputs = {
  cluster_endpoint = replace(dependency.eks.outputs.cluster_endpoint, "https://", "")

  cilium_version = "1.16.5"

  replace_kube_proxy = try(local.blockchain_config.cilium_replace_kube_proxy, false)

  # Hubble observability
  enable_hubble    = true
  enable_hubble_ui = true

  # Prometheus integration
  enable_service_monitor = true

  # ENI prefix delegation for higher pod density
  enable_prefix_delegation = true

  # Bandwidth manager for QoS — critical for blockchain P2P networking
  enable_bandwidth_manager = true

  # Default deny policy
  enable_default_deny = false

  # HA for operator
  operator_replicas = local.environment == "prod" ? 2 : 1
}
