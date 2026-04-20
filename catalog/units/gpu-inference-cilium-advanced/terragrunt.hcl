# ---------------------------------------------------------------------------------------------------------------------
# GPU Inference Cilium Advanced eBPF — Catalog Unit (Issue #144)
# ---------------------------------------------------------------------------------------------------------------------
# Extends the base gpu-inference-cilium unit with advanced eBPF capabilities:
#   - Socket-level LB (sockops): zero NAT east-west — connect() rewritten once
#   - XDP + DSR: north-south LB at NIC level, return traffic skips NLB
#   - Maglev consistent hashing: connection affinity for long-lived gRPC/NCCL
#   - Hubble L7: selective HTTP visibility for vLLM, DNS-only for training
#   - ClusterMesh: gpu-inference cluster (ID=4) joins the platform mesh
#
# This unit manages monitoring resources and identity policies.
# The Helm values for socket LB / XDP / DSR / Hubble L7 / ClusterMesh are
# controlled via the gpu-inference-cilium unit (main Helm release).
#
# Deployment order (terragrunt.stack.hcl):
#   gpu-inference-cilium → gpu-inference-cilium-encryption → gpu-inference-cilium-advanced
#
# ClusterMesh post-steps (after apply):
#   1. Retrieve TLS certs from each cluster's clustermesh-apiserver-remote-cert secret
#   2. Populate remote_clusters endpoints in _global/clustermesh-connect/terragrunt.hcl
#   3. Run: cilium clustermesh status --wait (from any cluster context)
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/project/platform-design/terraform/modules/gpu-inference-cilium-advanced"
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  environment = local.account_vars.locals.environment
  aws_region  = local.region_vars.locals.aws_region
}

# ---------------------------------------------------------------------------------------------------------------------
# DEPENDENCIES
# ---------------------------------------------------------------------------------------------------------------------

dependency "eks" {
  config_path = "../gpu-inference-eks"

  mock_outputs = {
    cluster_name                       = "mock-gpu-cluster"
    cluster_endpoint                   = "https://mock-endpoint.eks.amazonaws.com"
    cluster_certificate_authority_data = "bW9jay1jZXJ0LWRhdGE="
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

# ---------------------------------------------------------------------------------------------------------------------
# PROVIDER GENERATION
# ---------------------------------------------------------------------------------------------------------------------

generate "k8s_providers" {
  path      = "k8s_providers_override.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-PROVIDERS
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
# INPUTS
# ---------------------------------------------------------------------------------------------------------------------

inputs = {
  tags = {
    Environment = local.environment
    ClusterRole = "gpu-inference"
    Feature     = "cilium-advanced-ebpf"
    ManagedBy   = "terragrunt"
  }
}
