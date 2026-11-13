include "root" {
  path = find_in_parent_folders("root.hcl")
}

# ---------------------------------------------------------------------------------------------------------------------
# OVHcloud MKS ArgoCD — Catalog Unit (Reuses terraform/modules/argocd)
# ---------------------------------------------------------------------------------------------------------------------
# Reuses `terraform/modules/argocd` to deploy ArgoCD onto the MKS system node pool so
# `argocd/applicationset-gpu-inference.yaml` reconciles cluster addons and workloads.
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/terraform/modules/argocd"
}

locals {
  project_vars = read_terragrunt_config(find_in_parent_folders("project.hcl"))

  environment          = local.project_vars.locals.environment
  gpu_inference_config = try(local.project_vars.locals.gpu_inference_config, {})
}

dependency "mks" {
  config_path = "../ovh-mks-gpu"

  mock_outputs = {
    cluster_name           = "mock-ovh-mks"
    cluster_endpoint       = "https://127.0.0.1:6443"
    cluster_ca_certificate = "bW9jay1jZXJ0LWRhdGE="
    client_certificate     = "bW9jay1jZXJ0LWRhdGE="
    client_key             = "bW9jay1rZXktZGF0YQ=="
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

generate "ovh_k8s_providers" {
  path      = "ovh_k8s_providers_override.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-PROVIDERS
    provider "helm" {
      kubernetes {
        host                   = "${dependency.mks.outputs.cluster_endpoint}"
        client_certificate     = base64decode("${dependency.mks.outputs.client_certificate}")
        client_key             = base64decode("${dependency.mks.outputs.client_key}")
        cluster_ca_certificate = base64decode("${dependency.mks.outputs.cluster_ca_certificate}")
      }
    }

    provider "kubernetes" {
      host                   = "${dependency.mks.outputs.cluster_endpoint}"
      client_certificate     = base64decode("${dependency.mks.outputs.client_certificate}")
      client_key             = base64decode("${dependency.mks.outputs.client_key}")
      cluster_ca_certificate = base64decode("${dependency.mks.outputs.cluster_ca_certificate}")
    }
  PROVIDERS
}

inputs = {
  ha_enabled = try(local.gpu_inference_config.argocd_ha_enabled, local.environment == "prod")
  enable_dex = false

  additional_helm_values = {
    crds = {
      install = true
    }
    controller = {
      metrics = {
        serviceMonitor = {
          enabled = false
        }
      }
    }
    server = {
      metrics = {
        serviceMonitor = {
          enabled = false
        }
      }
    }
    repoServer = {
      metrics = {
        serviceMonitor = {
          enabled = false
        }
      }
    }
  }

  tags = {
    Environment = local.environment
    ManagedBy   = "terragrunt"
  }
}
