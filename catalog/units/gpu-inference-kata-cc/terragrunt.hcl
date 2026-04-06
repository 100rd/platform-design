# ---------------------------------------------------------------------------------------------------------------------
# GPU Inference Kata CC — Catalog Unit
# ---------------------------------------------------------------------------------------------------------------------
# Deploys Kata Containers v3.22 RuntimeClass, CiliumNetworkPolicy, and
# attestation ConfigMap for GPU Confidential Computing workloads on the
# gpu-inference cluster.
#
# Kata CC wraps each pod in a hardware-attested micro-VM (TDX/SEV-SNP),
# protecting GPU memory (model weights, KV cache, inference data) from
# host-level access. Requires CC-capable GPU nodes labeled
# nvidia.com/cc.enabled=true.
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/project/platform-design/terraform/modules/gpu-inference-kata-cc"
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
  kata_version = "3.22.0"

  # Attestation service — override per environment
  attestation_service_url      = try(local.gpu_inference_config.kata_cc_attestation_url, "https://attestation.example.internal:8443")
  attestation_tee_type         = try(local.gpu_inference_config.kata_cc_tee_type, "tdx")
  attestation_policy_namespace = "gpu-inference-cc"

  # Namespace where vLLM CC pods run
  cc_namespace = "gpu-inference"
  cc_app_label = "vllm-cc"

  tags = {
    Environment = local.environment
    ClusterRole = "gpu-inference"
    Feature     = "confidential-computing"
    ManagedBy   = "terragrunt"
  }
}
