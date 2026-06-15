# ---------------------------------------------------------------------------------------------------------------------
# aws-eks-inference-gateway — Catalog Unit (WS-A — ml-platform)
# ---------------------------------------------------------------------------------------------------------------------
# Model-/KV-cache-aware serving front (Envoy Gateway + InferencePool/InferenceObjective
# + EPP) fronted by AWS WAF (ADR-0047). Depends on aws-eks-gpu (+ the reused waf WebACL
# ARN via account.hcl). Default-OFF (apply-gated; keeps the vLLM ClusterIP until proven).
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/terraform/modules/aws-eks-inference-gateway"
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  environment         = local.account_vars.locals.environment
  gpu_platform_config = try(local.account_vars.locals.gpu_platform_config, {})
}

dependency "eks" {
  config_path = "../aws-eks-gpu"

  mock_outputs = {
    cluster_name                       = "mock-cluster"
    cluster_endpoint                   = "https://mock-endpoint.eks.amazonaws.com"
    cluster_certificate_authority_data = ""
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
  enabled    = try(local.gpu_platform_config.enabled, false)
  data_plane = try(local.gpu_platform_config.serving_data_plane, "envoy")

  # AWS WAF WebACL ARN from the reused `waf` module (ADR-0047 D4), if provisioned.
  waf_web_acl_arn = try(local.gpu_platform_config.inference_waf_web_acl_arn, "")

  inference_objectives = try(local.gpu_platform_config.inference_objectives, [
    { name = "default-model", target_model = "default-model-v1", criticality = "Standard" },
  ])

  platform_labels = {
    "platform.env"   = local.environment
    "platform.owner" = "team-ml-platform"
  }
}
