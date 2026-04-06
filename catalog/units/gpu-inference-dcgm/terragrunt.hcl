# ---------------------------------------------------------------------------------------------------------------------
# GPU Inference DCGM Exporter v4.5 — Catalog Unit
# ---------------------------------------------------------------------------------------------------------------------
# Deploys NVIDIA DCGM Exporter as a DaemonSet on the gpu-inference EKS cluster
# with a custom metrics CSV for GPU utilisation, memory, temperature, power
# draw, XID errors, NVLink bandwidth, and ECC errors.
#
# When enable_auto_taint is true a CronJob polls XID errors every 2 minutes
# and taints nodes with gpu-health=unhealthy:NoSchedule to prevent new
# workloads landing on defective GPU hardware.
#
# PrometheusRule / VMRule alerts cover:
#   - XID errors exceeding threshold
#   - GPU temperature > 85 °C (configurable)
#   - Double-bit ECC errors
#   - NVLink bandwidth degradation
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/project/platform-design/terraform/modules/gpu-inference-dcgm"
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
  dcgm_exporter_version = try(local.gpu_inference_config.dcgm_exporter_version, "4.5.0")
  namespace             = "gpu-monitoring"

  # Health auto-tainting — enabled by default in prod
  enable_auto_taint     = try(local.gpu_inference_config.dcgm_enable_auto_taint, true)
  xid_error_threshold   = try(local.gpu_inference_config.dcgm_xid_error_threshold, 1)
  temperature_threshold = try(local.gpu_inference_config.dcgm_temperature_threshold, 85)

  # VictoriaMetrics is the metrics backend for the gpu-inference cluster
  use_vm_rule     = true
  alert_namespace = "monitoring"

  scrape_interval = "15s"

  tags = {
    Environment = local.environment
    ClusterRole = "gpu-inference"
    ManagedBy   = "terragrunt"
  }
}
