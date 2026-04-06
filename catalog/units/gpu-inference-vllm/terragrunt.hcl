# ---------------------------------------------------------------------------------------------------------------------
# vLLM v0.19 — GPU Inference Catalog Unit
# ---------------------------------------------------------------------------------------------------------------------
# Deploys vLLM v0.19 on the gpu-inference EKS cluster with:
#   - DRA ResourceClaimTemplate referencing the single-gpu-inference device class
#   - Volcano scheduler + gpu-inference-medium PriorityClass
#   - Multi-LoRA support (up to 8 simultaneous adapters)
#   - VMServiceScrape for VictoriaMetrics metrics collection
#
# Depends on: gpu-inference-eks (cluster endpoint + CA data)
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/project/platform-design/terraform/modules/gpu-inference-vllm"
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  environment          = local.account_vars.locals.environment
  aws_region           = local.region_vars.locals.aws_region
  gpu_inference_config = try(local.account_vars.locals.gpu_inference_config, {})
}

# ---------------------------------------------------------------------------------------------------------------------
# DEPENDENCY: GPU Inference EKS — cluster endpoint and credentials
# ---------------------------------------------------------------------------------------------------------------------

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

# ---------------------------------------------------------------------------------------------------------------------
# Kubernetes provider — authenticated against the gpu-inference cluster
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
# Module inputs
# ---------------------------------------------------------------------------------------------------------------------

inputs = {
  vllm_version         = try(local.gpu_inference_config.vllm_version, "0.19.0")
  replicas             = try(local.gpu_inference_config.vllm_replicas, 3)
  model_name           = try(local.gpu_inference_config.vllm_model_name, "meta-llama/Llama-3-70B-Instruct")
  tensor_parallel_size = try(local.gpu_inference_config.tensor_parallel_size, 8)
  max_model_len        = try(local.gpu_inference_config.max_model_len, 131072)
  enable_lora          = try(local.gpu_inference_config.enable_lora, true)
  max_loras            = try(local.gpu_inference_config.max_loras, 8)

  lora_modules = try(local.gpu_inference_config.lora_modules, [
    { name = "finance-adapter", path = "/lora-adapters/finance-v1" },
    { name = "code-adapter", path = "/lora-adapters/code-v2" },
    { name = "summarization-adapter", path = "/lora-adapters/summarization-v1" },
  ])

  gpu_memory_utilization       = try(local.gpu_inference_config.gpu_memory_utilization, 0.92)
  namespace                    = "gpu-inference"
  resource_claim_template_name = "single-gpu-inference"
  scheduler_name               = "volcano"
  priority_class_name          = "gpu-inference-medium"

  tags = {
    Environment = local.environment
    ClusterRole = "gpu-inference"
    ManagedBy   = "terragrunt"
  }
}
