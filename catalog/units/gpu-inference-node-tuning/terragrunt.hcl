# ---------------------------------------------------------------------------------------------------------------------
# GPU Inference Node Tuning — Catalog Unit
# ---------------------------------------------------------------------------------------------------------------------
# Configures OS-level performance tuning for GPU inference nodes:
# CPU isolation, 1GB HugePages, NUMA-aware topology, NCCL network buffers.
#
# Creates ConfigMaps (Bottlerocket settings, kubelet config, sysctl) and
# a validator DaemonSet that verifies tuning is correctly applied on GPU nodes.
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/project/platform-design/terraform/modules/gpu-node-tuning"
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  environment          = local.account_vars.locals.environment
  aws_region           = local.region_vars.locals.aws_region
  gpu_inference_config = try(local.account_vars.locals.gpu_inference_config, {})
}

dependency "eks" {
  config_path = "../gpu-inference-eks"

  mock_outputs = {
    cluster_name                       = "mock-cluster"
    cluster_endpoint                   = "https://mock-endpoint.eks.amazonaws.com"
    cluster_certificate_authority_data = "bW9jay1jZXJ0LWRhdGE="
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

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

inputs = {
  # CPU isolation for p5.48xlarge (192 vCPUs)
  # Reserve 0-3 for system, isolate 4-191 for workloads
  reserved_system_cpus = try(local.gpu_inference_config.reserved_system_cpus, "0-3")
  isolated_cpus        = try(local.gpu_inference_config.isolated_cpus, "4-191")

  # 1GB HugePages for vLLM model weight loading
  hugepage_size   = "1G"
  hugepages_count = try(local.gpu_inference_config.hugepages_count, 1536)

  # Resource reservations
  kube_reserved_cpu      = "2"
  kube_reserved_memory   = "4Gi"
  system_reserved_cpu    = "2"
  system_reserved_memory = "4Gi"

  tags = {
    Environment = local.environment
    ClusterRole = "gpu-inference"
    ManagedBy   = "terragrunt"
  }
}
