# ---------------------------------------------------------------------------------------------------------------------
# baremetal-ml-artifact-store — Catalog Unit (WS-B — ml-pipeline, bare metal)
# ---------------------------------------------------------------------------------------------------------------------
# Provisions the MinIO/Ceph-RGW S3 artifact store + ESO-backed S3 credential for
# MLflow on the bare-metal Talos cluster.
#
# This is the bare-metal analogue of catalog/units/ml-artifact-store (GCS/WI).
# Storage substrate: MinIO (UK-DC pools, existing) or Ceph-RGW (if ADR-0052
# Rook-Ceph is deployed). S3-compatible API — no code change in MLflow or GH Actions.
#
# Dependencies (in WS-A / baremetal-gpu-analysis stack):
#   - talos-cluster  (kubeconfig / cluster endpoint)
#   - baremetal-rook-ceph (Ceph-RGW endpoint, if backend = ceph-rgw)
#
# Requires site.hcl with: dc_name, environment
# Requires region.hcl (optional) or hard-coded UK DC names.
#
# ADR-0028: all K8s-plane labels use dotted keys (platform.system = ml-pipeline).
# ADR-0037: orchestrator/registry design reused; only the substrate changes.
# ADR-0052: MinIO (default) or Ceph-RGW; both S3-compatible.
# ADR-0049: UK-isolated ML control plane.
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/terraform/modules/baremetal-ml-artifact-store"
}

locals {
  site_vars = read_terragrunt_config(find_in_parent_folders("site.hcl"))

  dc_name     = local.site_vars.locals.dc_name     # e.g. "uk-primary" or "uk-standby"
  environment = local.site_vars.locals.environment # e.g. "prod"

  ml_pipeline_config = try(local.site_vars.locals.ml_pipeline_config, {})
}

# ---------------------------------------------------------------------------------------------------------------------
# DEPENDENCY: Talos cluster (kubeconfig + endpoint from WS-A talos-cluster unit).
# The kubernetes / helm providers are generated below using the cluster outputs.
# ---------------------------------------------------------------------------------------------------------------------

dependency "talos_cluster" {
  config_path = "../talos-cluster"

  mock_outputs = {
    kubeconfig_raw = "apiVersion: v1\nclusters: []\ncontexts: []\nkind: Config\nusers: []"
    endpoint       = "https://10.0.0.1:6443"
    ca_certificate = "bW9jay1jYS1jZXJ0"
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

# ---------------------------------------------------------------------------------------------------------------------
# PROVIDERS: Talos-authenticated helm + kubernetes via in-cluster kubeconfig.
# The kubeconfig is materialised by talos-cluster (talos_cluster_kubeconfig).
# No GCP token, no static credentials — pure K8s API auth.
# ---------------------------------------------------------------------------------------------------------------------

generate "baremetal_providers" {
  path      = "baremetal_providers_override.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-PROVIDERS
    provider "kubernetes" {
      host                   = "${dependency.talos_cluster.outputs.endpoint}"
      client_certificate     = ""
      client_key             = ""
      cluster_ca_certificate = base64decode("${dependency.talos_cluster.outputs.ca_certificate}")
      # kubeconfig_path is set at plan time by KUBECONFIG env var in CI.
      # In plan-only mode (mock) the provider is exercised against mock outputs.
    }

    provider "helm" {
      kubernetes {
        host                   = "${dependency.talos_cluster.outputs.endpoint}"
        cluster_ca_certificate = base64decode("${dependency.talos_cluster.outputs.ca_certificate}")
      }
    }
  PROVIDERS
}

# ---------------------------------------------------------------------------------------------------------------------
# MODULE INPUTS
# ---------------------------------------------------------------------------------------------------------------------

inputs = {
  # APPLY-GATED: enabled = false by default in this catalog unit.
  # Set to true only after WS-A (talos-cluster + baremetal-rook-ceph / MinIO) is verified.
  enabled = try(local.ml_pipeline_config.artifact_store_enabled, false)

  backend         = try(local.ml_pipeline_config.artifact_store_backend, "minio")
  s3_endpoint_url = try(local.ml_pipeline_config.s3_endpoint_url, "http://minio.minio-system.svc.cluster.local:9000")
  bucket_name     = try(local.ml_pipeline_config.artifact_bucket_name, "mlflow-artifacts-${local.environment}")
  vault_path      = try(local.ml_pipeline_config.vault_s3_path, "secret/data/ml-pipeline/mlflow-s3-credentials")

  cluster_secret_store_name = try(local.ml_pipeline_config.cluster_secret_store_name, "vault-cluster-store")

  namespace                  = try(local.ml_pipeline_config.mlflow_namespace, "ml-pipeline")
  kubernetes_service_account = try(local.ml_pipeline_config.mlflow_k8s_sa, "mlflow")
  secret_name                = try(local.ml_pipeline_config.s3_secret_name, "mlflow-s3-credentials")

  minio_deploy_in_cluster = try(local.ml_pipeline_config.minio_deploy_in_cluster, false)
  minio_storage_class     = try(local.ml_pipeline_config.minio_storage_class, "rook-ceph-block")

  retention_days = try(local.ml_pipeline_config.artifact_retention_days, 365)

  # ADR-0028 K8s-plane labels (dotted keys; underscore label keys reserved for Terraform-plane resources).
  platform_labels = {
    "platform.env"   = local.environment
    "platform.owner" = try(local.ml_pipeline_config.owner, "team-ml")
  }
}
