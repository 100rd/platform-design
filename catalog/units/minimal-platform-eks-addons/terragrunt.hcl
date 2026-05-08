# ---------------------------------------------------------------------------------------------------------------------
# Minimal Platform EKS Addons — Catalog Unit
# ---------------------------------------------------------------------------------------------------------------------
# Deploys EKS managed addons that require running nodes (e.g. CoreDNS).
# Must be applied AFTER minimal-platform-eks-nodes.
#
# Deploy order:
#   vpc -> kms -> eks-cluster -> cilium -> eks-nodes -> eks-addons (this unit)
#
# Why CoreDNS lives here and not in eks-cluster:
#   aws_eks_addon waits for the addon to reach ACTIVE status. ACTIVE requires
#   the addon pods to be Running. CoreDNS is a Deployment — it needs Ready nodes.
#   Attempting to deploy CoreDNS before nodes exist causes the eks-cluster apply
#   to block indefinitely waiting for the addon to become ACTIVE.
#
# The CoreDNS configuration override adds a toleration for the Cilium startup
# taint (node.cilium.io/agent-not-ready:NoExecute) so CoreDNS pods are
# scheduled on nodes that have joined but whose Cilium agent is still
# initialising. Without this toleration CoreDNS stays Pending until the taint
# is removed, which can block cluster DNS for the first few minutes.
# ---------------------------------------------------------------------------------------------------------------------

# Include root.hcl to activate remote_state (S3 backend generation) and provider
# generation. Without this block, terragrunt ignores root.hcl entirely — no
# backend.tf is generated and state falls back to local storage.
include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_repo_root()}/terraform/modules/eks-addons"
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  environment = local.account_vars.locals.environment
}

# ---------------------------------------------------------------------------------------------------------------------
# DEPENDENCY: Minimal Platform EKS Cluster — provides cluster_name
# ---------------------------------------------------------------------------------------------------------------------

dependency "eks_cluster" {
  config_path = "../eks-cluster"

  mock_outputs = {
    cluster_name = "mock-cluster"
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

# ---------------------------------------------------------------------------------------------------------------------
# SOFT DEPENDENCY: Minimal Platform EKS Nodes
# Ensures nodes are Ready before addons are deployed. skip_outputs = true
# because we do not consume any eks-nodes outputs in this unit.
# ---------------------------------------------------------------------------------------------------------------------

dependency "eks_nodes" {
  config_path  = "../eks-nodes"
  skip_outputs = true
}

# ---------------------------------------------------------------------------------------------------------------------
# MODULE INPUTS
# ---------------------------------------------------------------------------------------------------------------------

inputs = {
  cluster_name = dependency.eks_cluster.outputs.cluster_name

  addons = {
    coredns = {
      # Allow CoreDNS pods to schedule on nodes that carry the Cilium startup
      # taint. Without this override, CoreDNS stays Pending until the Cilium
      # agent removes the taint — which itself requires DNS to be functional.
      # The toleration breaks this circular dependency.
      configuration_values = jsonencode({
        tolerations = [
          {
            key      = "node.cilium.io/agent-not-ready"
            operator = "Exists"
            effect   = "NoExecute"
          }
        ]
      })
    }
  }

  tags = {
    Environment = local.environment
    ManagedBy   = "terragrunt"
  }
}
