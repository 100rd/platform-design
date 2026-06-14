# ---------------------------------------------------------------------------------------------------------------------
# ClusterMesh Connect — Catalog Unit
# ---------------------------------------------------------------------------------------------------------------------
# Creates the cross-cluster ClusterMesh connection secret(s) on THIS cluster, one per
# remote peer. Each secret holds the peer clustermesh-apiserver endpoint + the peer's
# etcd CA / client cert / client key, which Cilium uses to join the mesh.
#
# Peer TLS material is read from AWS Secrets Manager (cross-region cert exchange), driven
# by account.hcl `clustermesh_remote_clusters[<this-region>]`. The whole thing is gated by
# `clustermesh_connect_enabled` (default false) so plan/validate stay offline until the
# certs have been exchanged into Secrets Manager (see docs/runbooks/cilium-clustermesh-connect.md).
#
# Dependencies: eks (provider auth), cilium (must be up so the local apiserver + CA exist).
# Requires account.hcl: enable_clustermesh, clustermesh_connect_enabled, clustermesh_remote_clusters.
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/terraform/modules/clustermesh-connect"
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  environment = local.account_vars.locals.environment
  aws_region  = local.region_vars.locals.aws_region

  connect_enabled = try(local.account_vars.locals.clustermesh_connect_enabled, false)

  # Remote peers for THIS region (list of objects); empty unless configured.
  remote_peers = try(local.account_vars.locals.clustermesh_remote_clusters[local.aws_region], [])
}

# ---------------------------------------------------------------------------------------------------------------------
# DEPENDENCIES
# ---------------------------------------------------------------------------------------------------------------------

dependency "eks" {
  config_path = "../eks"

  mock_outputs = {
    cluster_endpoint                   = "https://XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX.gr7.eu-west-1.eks.amazonaws.com"
    cluster_certificate_authority_data = ""
    cluster_name                       = "staging-eu-west-1-platform"
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

dependency "cilium" {
  config_path = "../cilium"

  mock_outputs = {
    clustermesh_enabled = true
    cluster_mesh_name   = "staging-euw1"
    cluster_mesh_id     = 1
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

# ---------------------------------------------------------------------------------------------------------------------
# PROVIDERS: kubernetes (creates the ClusterMesh secret) + aws (reads peer certs from Secrets Manager)
# ---------------------------------------------------------------------------------------------------------------------

generate "providers" {
  path      = "providers_override.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-PROVIDERS
    provider "aws" {
      region = "${local.aws_region}"
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
  # Build the secrets-backed remote map from account.hcl, gated by clustermesh_connect_enabled.
  remote_clusters_from_secrets = local.connect_enabled ? {
    for p in local.remote_peers : p.name => {
      endpoint       = p.endpoint
      ca_secret_id   = p.ca_secret_id
      cert_secret_id = p.cert_secret_id
      key_secret_id  = p.key_secret_id
    }
  } : {}
}
