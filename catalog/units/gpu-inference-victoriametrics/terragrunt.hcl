# ---------------------------------------------------------------------------------------------------------------------
# VictoriaMetrics Operator v0.68 — GPU Inference Metrics Catalog Unit
# ---------------------------------------------------------------------------------------------------------------------
# Deploys VictoriaMetrics Operator and VMCluster CR in cluster mode for
# high-scale metrics collection from 5000 GPU nodes.
#
# Cluster mode splits insert, select, and storage into independently
# scalable components, supporting sustained high-cardinality ingest from
# DCGM exporters, Cilium, and kubelet/cAdvisor across the fleet.
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/project/platform-design/terraform/modules/gpu-inference-victoriametrics"
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

inputs = {
  # VictoriaMetrics Operator chart version (maps to operator v0.68)
  operator_chart_version = "0.59.3"

  # Retention — 30 days default; increase for longer-term capacity analysis
  retention_period = try(local.gpu_inference_config.vm_retention_period, "30d")

  # Replica counts — 3 for HA across 3 AZs
  vminsert_replicas  = try(local.gpu_inference_config.vminsert_replicas, 3)
  vmselect_replicas  = try(local.gpu_inference_config.vmselect_replicas, 3)
  vmstorage_replicas = try(local.gpu_inference_config.vmstorage_replicas, 3)

  # Storage — gp3 for cost-effective throughput; 500Gi per replica
  storage_class = try(local.gpu_inference_config.vm_storage_class, "gp3")
  storage_size  = try(local.gpu_inference_config.vm_storage_size, "500Gi")

  tags = {
    Environment = local.environment
    ClusterRole = "gpu-inference"
    Component   = "monitoring"
    ManagedBy   = "terragrunt"
  }
}
