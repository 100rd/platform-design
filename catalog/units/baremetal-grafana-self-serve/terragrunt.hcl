# ---------------------------------------------------------------------------------------------------------------------
# Bare-Metal Grafana Self-Serve RBAC — Catalog Unit (WS-D — bare-metal observability)
# ---------------------------------------------------------------------------------------------------------------------
# Provisions per-team RBAC on the Talos bare-metal cluster to enable self-serve
# observability without platform-team tickets:
#
#   1. PrometheusRule manager Role + RoleBinding (alert-rules-as-code)
#   2. Grafana dashboard ConfigMap writer Role + RoleBinding
#   3. Loki log-query ClusterRole + ClusterRoleBinding (bare-metal delta: RBAC-gated,
#      not IAM-gated as in cloud deployments)
#
# The kubernetes provider is wired to the cluster credentials from the
# talos-cluster catalog unit (kubeconfig / endpoint output). All resources are
# apply-gated via enabled=false by default — set to true explicitly per team
# in the live tree dc.hcl.
#
# Dependencies: catalog/units/talos-cluster (endpoint + ca_cert outputs)
#
# ADR-0039: Self-Serve Observability (reused for bare metal)
# ADR-0028: platform.system = observability (mandatory on every resource)
# ADR-0049: Talos foundation (target cluster)
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/terraform/modules/baremetal-grafana-self-serve"
}

locals {
  dc_vars  = read_terragrunt_config(find_in_parent_folders("dc.hcl"))
  env_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))

  environment    = local.env_vars.locals.environment
  self_serve_cfg = try(local.dc_vars.locals.self_serve_config, {})
}

# ---------------------------------------------------------------------------
# Dependency: talos-cluster provides the API endpoint and CA certificate
# used to configure the kubernetes provider at plan time.
# ---------------------------------------------------------------------------
dependency "talos_cluster" {
  config_path = "../talos-cluster"

  mock_outputs = {
    endpoint = "https://10.0.0.1:6443"
    ca_cert  = "bW9jay1jZXJ0LWRhdGE="
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

# ---------------------------------------------------------------------------
# Generate the kubernetes provider block at unit level.
# Credentials are sourced from Vault/ESO in CI — no static kubeconfig.
# ---------------------------------------------------------------------------
generate "kubernetes_provider" {
  path      = "kubernetes_provider_override.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-PROVIDER
    provider "kubernetes" {
      host                   = "${dependency.talos_cluster.outputs.endpoint}"
      cluster_ca_certificate = base64decode("${dependency.talos_cluster.outputs.ca_cert}")
      # Credentials: set KUBE_TOKEN (SA token) or KUBECONFIG in the CI secrets step.
      # No static kubeconfig is committed per ADR-0049 security posture.
    }
  PROVIDER
}

# ---------------------------------------------------------------------------
# Module inputs
# ---------------------------------------------------------------------------
inputs = {
  # Default OFF — explicitly enabled per team in the live tree dc.hcl.
  # This satisfies the plan's apply-gated / default-OFF convention.
  enabled = try(local.self_serve_cfg.enabled, false)

  team_slug          = try(local.self_serve_cfg.team_slug, "")
  team_namespace     = try(local.self_serve_cfg.team_namespace, "")
  ci_service_account = try(local.self_serve_cfg.ci_service_account, "")
  grafana_namespace  = try(local.self_serve_cfg.grafana_namespace, "observability")

  grafana_service_account = try(local.self_serve_cfg.grafana_service_account, "")
  loki_namespace          = try(local.self_serve_cfg.loki_namespace, "observability")
  create_loki_access      = try(local.self_serve_cfg.create_loki_access, true)

  # ADR-0028 platform taxonomy labels (dotted form for K8s labels on bare metal).
  platform_labels = {
    "platform.system"  = "observability"
    "platform.env"     = local.environment
    "platform.owner"   = try(local.self_serve_cfg.team_slug, "platform")
  }
}
