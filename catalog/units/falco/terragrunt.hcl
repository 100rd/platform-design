# ---------------------------------------------------------------------------------------------------------------------
# Falco — Catalog Unit
# ---------------------------------------------------------------------------------------------------------------------
# Deploys Falco runtime security and file integrity monitoring via Helm.
# Includes PCI-DSS custom rules for threat detection and FIM.
#
# Depends on EKS cluster.
#
# PCI-DSS Requirements:
#   Req 5.1/5.2  — Anti-malware (crypto miners, reverse shells)
#   Req 10.2     — Audit logging (sensitive file access)
#   Req 11.5     — File Integrity Monitoring (system binary changes)
#
# Required inputs from account.hcl (optional overrides):
#   falco_chart_version     — Helm chart version (default: "4.16.1")
#   falco_driver_kind       — Driver type (default: "modern_ebpf")
#   falco_enable_sidekick   — Enable Falcosidekick (default: true)
#   falco_custom_rules      — Enable PCI-DSS custom rules (default: true)
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/project/platform-design/terraform/modules/falco"
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
  config_path = "../eks"

  mock_outputs = {
    cluster_name                       = "mock-cluster"
    cluster_endpoint                   = "https://mock-endpoint.eks.amazonaws.com"
    cluster_certificate_authority_data = "bW9jay1jZXJ0LWRhdGE="
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

# ---------------------------------------------------------------------------------------------------------------------
# Kubernetes / Helm providers
# ---------------------------------------------------------------------------------------------------------------------

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

# ---------------------------------------------------------------------------------------------------------------------
# MODULE INPUTS
# ---------------------------------------------------------------------------------------------------------------------

inputs = {
  chart_version        = try(local.account_vars.locals.falco_chart_version, "4.16.1")
  namespace            = "falco-system"
  create_namespace     = true
  enable_sidekick      = try(local.account_vars.locals.falco_enable_sidekick, true)
  driver_kind          = try(local.account_vars.locals.falco_driver_kind, "modern_ebpf")
  custom_rules_enabled = try(local.account_vars.locals.falco_custom_rules, true)
  log_level            = try(local.account_vars.locals.falco_log_level, "info")
  minimum_priority     = try(local.account_vars.locals.falco_minimum_priority, "warning")

  custom_rules_yaml = file("${get_repo_root()}/project/platform-design/kubernetes/security/falco-pci-rules.yaml")

  tags = {
    Environment   = local.environment
    ManagedBy     = "terragrunt"
    PCI_DSS_Scope = "true"
    Component     = "runtime-security"
  }
}
