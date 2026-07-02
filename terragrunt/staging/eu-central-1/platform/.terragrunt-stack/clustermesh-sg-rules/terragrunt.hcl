# ---------------------------------------------------------------------------------------------------------------------
# ClusterMesh Security Group Rules — Catalog Unit
# ---------------------------------------------------------------------------------------------------------------------
# Adds ingress rules to the EKS node security group for Cilium ClusterMesh
# cross-cluster traffic (etcd API, health, WireGuard, Hubble relay).
# Gated by enable_clustermesh in account.hcl.
# Depends on EKS cluster for node_security_group_id.
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/terraform/modules/clustermesh-sg-rules"
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
    node_security_group_id = "sg-mock"
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

inputs = {
  enabled                = try(local.account_vars.locals.enable_clustermesh, false)
  node_security_group_id = dependency.eks.outputs.node_security_group_id
  peer_vpc_cidrs         = try(local.account_vars.locals.peer_vpc_cidrs, {})

  tags = {
    Environment = local.environment
    ManagedBy   = "terragrunt"
  }
}
