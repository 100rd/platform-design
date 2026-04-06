# ---------------------------------------------------------------------------------------------------------------------
# GPU Inference HPA — Catalog Unit
# ---------------------------------------------------------------------------------------------------------------------
# Deploys Prometheus Adapter (pointed at VictoriaMetrics vmselect) and a custom HPA for the
# vLLM Deployment.  Depends on the gpu-inference EKS cluster unit.
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/project/platform-design/terraform/modules/gpu-inference-hpa"
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  account_name = local.account_vars.locals.account_name
  aws_region   = local.region_vars.locals.aws_region
  environment  = local.account_vars.locals.environment
}

# ---------------------------------------------------------------------------------------------------------------------
# DEPENDENCY: EKS
# ---------------------------------------------------------------------------------------------------------------------

dependency "eks" {
  config_path = "../gpu-inference-eks"

  mock_outputs = {
    cluster_name                       = "mock-gpu-inference"
    cluster_endpoint                   = "https://mock-endpoint.eks.amazonaws.com"
    cluster_certificate_authority_data = "bW9jay1jZXJ0LWRhdGE="
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

# ---------------------------------------------------------------------------------------------------------------------
# PROVIDERS: Helm + Kubernetes (both needed — Helm to deploy the adapter, K8s for the HPA resource)
# ---------------------------------------------------------------------------------------------------------------------

generate "k8s_helm_providers" {
  path      = "k8s_helm_providers_override.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-PROVIDERS
    provider "helm" {
      kubernetes {
        host                   = "${dependency.eks.outputs.cluster_endpoint}"
        cluster_ca_certificate = base64decode("${dependency.eks.outputs.cluster_certificate_authority_data}")
        exec {
          api_version = "client.authentication.k8s.io/v1beta1"
          command     = "aws"
          args        = ["eks", "get-token", "--cluster-name", "${dependency.eks.outputs.cluster_name}"]
        }
      }
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
  cluster_name = dependency.eks.outputs.cluster_name

  # VictoriaMetrics vmselect endpoint.  Override per-environment in account.hcl via:
  #   vmselect_url = "http://vmselect.monitoring.svc.cluster.local:8481/select/0/prometheus"
  vmselect_url = try(
    local.account_vars.locals.vmselect_url,
    "http://vmselect.monitoring.svc.cluster.local:8481/select/0/prometheus"
  )

  min_replicas       = try(local.account_vars.locals.vllm_min_replicas, 2)
  max_replicas       = try(local.account_vars.locals.vllm_max_replicas, 50)
  queue_depth_target = try(local.account_vars.locals.vllm_queue_depth_target, 5)
  cache_usage_target = try(local.account_vars.locals.vllm_cache_usage_target, 80)
}
