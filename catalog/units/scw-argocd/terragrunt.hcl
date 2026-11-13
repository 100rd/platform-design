include "root" {
  path = find_in_parent_folders("root.hcl")
}

# ---------------------------------------------------------------------------------------------------------------------
# Scaleway Kapsule ArgoCD — Catalog Unit (Reuses terraform/modules/argocd)
# ---------------------------------------------------------------------------------------------------------------------
# Reuses the existing `terraform/modules/argocd` Helm module to deploy ArgoCD onto the
# Scaleway Kapsule system node pool so GitOps ApplicationSets (`argocd/applicationset-gpu-inference.yaml`)
# reconcile cluster addons and inference workloads from `apps/infra/*`.
#
# Dependencies: scw-kapsule-gpu
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/terraform/modules/argocd"
}

locals {
  project_vars = read_terragrunt_config(find_in_parent_folders("project.hcl"))

  environment          = local.project_vars.locals.environment
  gpu_inference_config = try(local.project_vars.locals.gpu_inference_config, {})
}

dependency "kapsule" {
  config_path = "../scw-kapsule-gpu"

  mock_outputs = {
    cluster_name           = "mock-scw-kapsule"
    cluster_endpoint       = "https://127.0.0.1:6443"
    cluster_ca_certificate = "bW9jay1jZXJ0LWRhdGE="
    kubeconfig_token       = "mock-token"
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

generate "scw_k8s_providers" {
  path      = "scw_k8s_providers_override.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-PROVIDERS
    provider "helm" {
      kubernetes {
        host                   = "${dependency.kapsule.outputs.cluster_endpoint}"
        token                  = "${dependency.kapsule.outputs.kubeconfig_token}"
        cluster_ca_certificate = base64decode("${dependency.kapsule.outputs.cluster_ca_certificate}")
      }
    }

    provider "kubernetes" {
      host                   = "${dependency.kapsule.outputs.cluster_endpoint}"
      token                  = "${dependency.kapsule.outputs.kubeconfig_token}"
      cluster_ca_certificate = base64decode("${dependency.kapsule.outputs.cluster_ca_certificate}")
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
