# -------------------------------------------------------------------------
# Catalog Unit: baremetal-ml-monitoring — WS-C (ADR-0038, ADR-0049)
# -------------------------------------------------------------------------
#
# Provisions the ArgoCD Application resources that deploy the ml-monitoring
# Helm chart onto the Talos UK bare-metal cluster.
#
# This unit is cluster-agnostic at the Terraform layer: it creates an ArgoCD
# Application object (via the kubernetes/kubectl provider targeting the ArgoCD
# cluster) rather than creating cloud resources. The actual in-cluster
# Evidently/whylogs Deployments, PrometheusRules, ServiceMonitors, and
# ExternalSecrets are rendered by Helm and managed by ArgoCD.
#
# ADR citations:
#   ADR-0038 — Evidently/whylogs drift monitoring (decision of record)
#   ADR-0049 — Bare-metal foundation; multi-DC scope; UK-resident data
#   ADR-0028 — Platform taxonomy labels (MANDATORY on all resources)
#
# APPLY GATE:
#   never_apply = true (set by CI profile).
#   plan/validate-only. No terragrunt apply without explicit human approval.
#   No ArgoCD sync without explicit human approval.
#
# DEPENDENCIES (in WS-A sequencing order):
#   talos-cluster        -> kubeconfig / cluster endpoint
#   baremetal-rook-ceph  -> MinIO/Ceph-RGW S3 endpoint (ADR-0052)
#   prometheus-stack     -> Prometheus CRDs (wave 10 before wave 20)
#   airflow (WS-B)       -> retrain webhook target
#   ESO ClusterSecretStore (WS-E) -> Vault-backed secret store
# -------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/terraform/modules/argocd-application"
}

locals {
  # Guarded reads: the dc.hcl / env.hcl live tree is wired per-datacenter at deploy
  # time. try() lets the catalog unit also validate standalone (CI) and fall back to
  # the primary-DC defaults until the live dc/env tree exists.
  dc_vars  = try(read_terragrunt_config(find_in_parent_folders("dc.hcl")), { locals = {} })
  env_vars = try(read_terragrunt_config(find_in_parent_folders("env.hcl")), { locals = {} })

  dc           = try(local.dc_vars.locals.dc_name, "uk-primary")      # "uk-primary" or "uk-standby"
  environment  = try(local.env_vars.locals.environment, "production") # "production"
  cluster_name = "talos-${local.dc}"                                  # "talos-uk-primary"
}

# -------------------------------------------------------------------------
# DEPENDENCY: Talos cluster (WS-A) — provides cluster endpoint
# -------------------------------------------------------------------------
dependency "talos_cluster" {
  config_path = "../talos-cluster"

  mock_outputs = {
    kubeconfig_path  = "/dev/null"
    cluster_endpoint = "https://mock-talos-endpoint.internal:6443"
    cluster_ca_cert  = "mock-ca-cert-base64"
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

# -------------------------------------------------------------------------
# DEPENDENCY: Rook-Ceph (WS-A, ADR-0052) — S3 endpoint for MinIO/RGW
# -------------------------------------------------------------------------
dependency "baremetal_rook_ceph" {
  config_path = "../baremetal-rook-ceph"

  mock_outputs = {
    rgw_s3_endpoint = "http://mock-rook-rgw.rook-ceph.svc.cluster.local:80"
    rgw_bucket_name = "ml-reference-data"
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

# -------------------------------------------------------------------------
# MODULE INPUTS
# -------------------------------------------------------------------------
inputs = {
  # ArgoCD Application name — disambiguated from cloud variant
  app_name         = "ml-monitoring-baremetal"
  argocd_namespace = "argocd"
  project          = "platform"

  # Source
  repo_url         = "https://github.com/your-org/platform-infrastructure.git"
  target_revision  = "main"
  chart_path       = "apps/infra/ml-monitoring"
  helm_value_files = ["values.yaml", "values-baremetal.yaml"]

  # Destination — Talos UK cluster registered in ArgoCD
  destination_server    = dependency.talos_cluster.outputs.cluster_endpoint
  destination_namespace = "ml-monitoring"

  # Sync wave: after prometheus-stack (10) and airflow/WS-B (15)
  sync_wave = 20

  # ADR-0028 labels (underscore form for Terraform resource tags)
  labels = {
    platform_system     = "ml-monitoring"
    platform_component  = "drift-exporter"
    platform_env        = local.environment
    platform_owner      = "team-ml-platform"
    platform_managed_by = "argocd"
    platform_cluster    = local.cluster_name
  }

  # Additional Helm values resolved from dependency outputs (substrate-specific)
  helm_set_values = {
    "platformLabels.platform\\.cluster"   = local.cluster_name
    "driftExporter.referenceBucketUri"    = "s3://${dependency.baremetal_rook_ceph.outputs.rgw_bucket_name}"
    "externalSecrets.secretStoreRef.name" = "vault-cluster-secret-store"
  }
}
