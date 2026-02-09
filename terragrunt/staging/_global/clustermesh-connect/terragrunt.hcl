# ---------------------------------------------------------------------------------------------------------------------
# ClusterMesh Connect — Live Deployment (Global)
# ---------------------------------------------------------------------------------------------------------------------
# Establishes Cilium ClusterMesh connectivity between EKS clusters in different regions.
# Shares CA certs and endpoint information between clusters via Kubernetes secrets.
#
# This is a cross-cluster operation — deploy AFTER Cilium is running in all regions.
#
# Prerequisites:
#   - Cilium with ClusterMesh enabled in both regions
#   - ClusterMesh API server NLBs accessible cross-region (via TGW)
#   - ClusterMesh SG rules allowing ports 2379, 4240, 51871, 4244
#
# Usage:
#   terragrunt plan
#   terragrunt apply
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/terraform/modules/clustermesh-connect"
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  environment  = local.account_vars.locals.environment
}

# ---------------------------------------------------------------------------------------------------------------------
# DEPENDENCIES: Cilium outputs from each region
# ---------------------------------------------------------------------------------------------------------------------

dependency "cilium_euw1" {
  config_path = "../../eu-west-1/platform/cilium"

  mock_outputs = {
    cluster_mesh_name  = "staging-euw1"
    cluster_mesh_id    = 1
    clustermesh_enabled = true
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

dependency "cilium_euc1" {
  config_path = "../../eu-central-1/platform/cilium"

  mock_outputs = {
    cluster_mesh_name  = "staging-euc1"
    cluster_mesh_id    = 2
    clustermesh_enabled = true
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

# ---------------------------------------------------------------------------------------------------------------------
# MODULE INPUTS
# ---------------------------------------------------------------------------------------------------------------------
# NOTE: CA certs and TLS credentials are populated post-deployment.
# After initial Cilium deployment with ClusterMesh enabled, retrieve certs from
# each cluster's kube-system/clustermesh-apiserver-remote-cert secret and populate
# these values. Alternatively, use cilium clustermesh connect --destination-context.
# ---------------------------------------------------------------------------------------------------------------------

inputs = {
  remote_clusters = {
    (dependency.cilium_euw1.outputs.cluster_mesh_name) = {
      endpoint = "" # ClusterMesh API server NLB DNS — populated post-deployment
      ca_cert  = "" # Retrieved from cluster secret post-deployment
      tls_cert = ""
      tls_key  = ""
    }
    (dependency.cilium_euc1.outputs.cluster_mesh_name) = {
      endpoint = "" # ClusterMesh API server NLB DNS — populated post-deployment
      ca_cert  = "" # Retrieved from cluster secret post-deployment
      tls_cert = ""
      tls_key  = ""
    }
  }
}
