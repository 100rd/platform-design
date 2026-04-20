# ---------------------------------------------------------------------------------------------------------------------
# ClusterMesh Connect — Prod (Global)
# ---------------------------------------------------------------------------------------------------------------------
# Establishes Cilium ClusterMesh connectivity between prod EKS clusters.
# Includes gpu-inference cluster (ID=4) added via Issue #144.
#
# Cluster ID assignments:
#   platform     = 1 (eu-west-1, eu-central-1 platform clusters)
#   blockchain   = 2
#   gpu-analysis = 3
#   gpu-inference = 4  ← NEW (Issue #144)
#
# Prerequisites:
#   - Cilium with ClusterMesh enabled on all clusters (gpu-inference-cilium unit)
#   - ClusterMesh API server NLBs in IP target mode (for DSR compatibility)
#   - Security group rules allowing ports: 2379 (etcd), 4240 (health), 51871 (WireGuard), 4244 (Hubble Relay)
#   - TGW connectivity between regions (TGW Connect from Issue #72)
#
# Post-deployment steps (manual — cert exchange cannot be automated):
#   1. From each cluster context:
#      kubectl get secret -n kube-system clustermesh-apiserver-remote-cert -o json | jq -r '.data."ca.crt"' | base64 -d
#   2. Populate ca_cert, tls_cert, tls_key below
#   3. Alternatively (simpler): cilium clustermesh connect --destination-context <context>
#
# Usage:
#   cd terragrunt/prod/_global/clustermesh-connect
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
# DEPENDENCIES: Cilium outputs from each cluster
# ---------------------------------------------------------------------------------------------------------------------

dependency "cilium_euw1_platform" {
  config_path = "../../eu-west-1/platform/cilium"

  mock_outputs = {
    cluster_mesh_name   = "prod-euw1-platform"
    cluster_mesh_id     = 1
    clustermesh_enabled = true
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

dependency "cilium_euc1_platform" {
  config_path = "../../eu-central-1/platform/cilium"

  mock_outputs = {
    cluster_mesh_name   = "prod-euc1-platform"
    cluster_mesh_id     = 1
    clustermesh_enabled = true
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

# gpu-inference cluster — added via Issue #144
dependency "cilium_euw1_gpu_inference" {
  config_path = "../../eu-west-1/gpu-inference/gpu-inference-cilium-advanced"

  mock_outputs = {
    cluster_mesh_name   = "prod-euw1-gpu"
    cluster_mesh_id     = 4
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
# these values. Alternatively, use: cilium clustermesh connect --destination-context
# ---------------------------------------------------------------------------------------------------------------------

inputs = {
  remote_clusters = {
    # Platform cluster — eu-west-1
    (dependency.cilium_euw1_platform.outputs.cluster_mesh_name) = {
      endpoint = "" # ClusterMesh API server NLB DNS — populated post-deployment
      ca_cert  = "" # kubectl get secret -n kube-system clustermesh-apiserver-remote-cert ...
      tls_cert = ""
      tls_key  = ""
    }
    # Platform cluster — eu-central-1
    (dependency.cilium_euc1_platform.outputs.cluster_mesh_name) = {
      endpoint = "" # ClusterMesh API server NLB DNS — populated post-deployment
      ca_cert  = ""
      tls_cert = ""
      tls_key  = ""
    }
    # GPU Inference cluster — eu-west-1 (Issue #144)
    (dependency.cilium_euw1_gpu_inference.outputs.cluster_mesh_name) = {
      endpoint = "" # ClusterMesh API server NLB DNS — populated post-deployment
      ca_cert  = "" # Retrieved from gpu-inference cluster's clustermesh-apiserver-remote-cert secret
      tls_cert = ""
      tls_key  = ""
    }
  }
}
