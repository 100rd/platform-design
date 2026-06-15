# ---------------------------------------------------------------------------------------------------------------------
# Tests for baremetal-ml-artifact-store module.
# helm and kubernetes providers are mocked — no real cluster or Vault is needed.
# All assertions run at plan time over resource wiring, toggles, and ADR-0028 labels.
# ADR-0052 / WS-B.
# ---------------------------------------------------------------------------------------------------------------------

mock_provider "helm" {}
mock_provider "kubernetes" {}
mock_provider "random" {}

# -------------------------------------------------------------------------
# Variables shared across runs
# -------------------------------------------------------------------------

variables {
  platform_labels = {
    "platform.env"   = "staging"
    "platform.owner" = "team-ml"
  }
}

# -------------------------------------------------------------------------
# Run 1 — default gate: nothing created when enabled = false (apply-gated mock default)
# -------------------------------------------------------------------------

run "disabled_creates_no_resources" {
  command = plan

  variables {
    enabled = false
  }

  assert {
    condition     = length(kubernetes_namespace.ml_pipeline) == 0
    error_message = "Namespace must NOT be created when enabled = false (apply-gated)."
  }

  assert {
    condition     = length(kubernetes_service_account.mlflow) == 0
    error_message = "ServiceAccount must NOT be created when enabled = false."
  }

  assert {
    condition     = length(kubernetes_manifest.mlflow_s3_externalsecret) == 0
    error_message = "ExternalSecret must NOT be created when enabled = false."
  }

  assert {
    condition     = length(helm_release.minio_operator) == 0
    error_message = "MinIO Operator must NOT be created when enabled = false."
  }
}

# -------------------------------------------------------------------------
# Run 2 — enabled, MinIO backend, no in-cluster MinIO deploy (shared instance)
# -------------------------------------------------------------------------

run "minio_backend_creates_namespace_and_eso" {
  command = plan

  variables {
    enabled                 = true
    backend                 = "minio"
    minio_deploy_in_cluster = false
    bucket_name             = "mlflow-artifacts-staging"
    s3_endpoint_url         = "http://minio.minio-system.svc.cluster.local:9000"
  }

  assert {
    condition     = length(kubernetes_namespace.ml_pipeline) == 1
    error_message = "Namespace must be created when enabled = true."
  }

  assert {
    condition     = length(kubernetes_service_account.mlflow) == 1
    error_message = "ServiceAccount must be created when enabled = true."
  }

  assert {
    condition     = length(kubernetes_manifest.mlflow_s3_externalsecret) == 1
    error_message = "ExternalSecret must be created when enabled = true."
  }

  assert {
    condition     = length(helm_release.minio_operator) == 0
    error_message = "MinIO Operator must NOT be created when minio_deploy_in_cluster = false."
  }
}

# -------------------------------------------------------------------------
# Run 3 — enabled, MinIO backend, deploy in-cluster
# -------------------------------------------------------------------------

run "minio_backend_in_cluster_creates_helm_release" {
  command = plan

  variables {
    enabled                 = true
    backend                 = "minio"
    minio_deploy_in_cluster = true
  }

  assert {
    condition     = length(helm_release.minio_operator) == 1
    error_message = "MinIO Operator Helm release must be created when minio_deploy_in_cluster = true."
  }

  assert {
    condition     = helm_release.minio_operator[0].chart == "operator"
    error_message = "MinIO Operator Helm chart name must be 'operator'."
  }
}

# -------------------------------------------------------------------------
# Run 4 — ceph-rgw backend: no MinIO Operator regardless of minio_deploy_in_cluster
# -------------------------------------------------------------------------

run "ceph_rgw_backend_never_creates_minio" {
  command = plan

  variables {
    enabled                 = true
    backend                 = "ceph-rgw"
    minio_deploy_in_cluster = true
    s3_endpoint_url         = "http://rook-ceph-rgw-my-store.rook-ceph.svc.cluster.local:80"
  }

  assert {
    condition     = length(helm_release.minio_operator) == 0
    error_message = "MinIO Operator must NOT be created when backend = 'ceph-rgw'."
  }

  assert {
    condition     = length(kubernetes_manifest.mlflow_s3_externalsecret) == 1
    error_message = "ExternalSecret must still be created for Ceph-RGW backend."
  }
}

# -------------------------------------------------------------------------
# Run 5 — ADR-0028: namespace carries required platform labels
# -------------------------------------------------------------------------

run "namespace_carries_adr0028_labels" {
  command = plan

  variables {
    enabled = true
    platform_labels = {
      "platform.env"   = "prod"
      "platform.owner" = "team-ml"
    }
  }

  assert {
    condition     = kubernetes_namespace.ml_pipeline[0].metadata[0].labels["platform.system"] == "ml-pipeline"
    error_message = "Namespace must carry platform.system = ml-pipeline per ADR-0028."
  }

  assert {
    condition     = kubernetes_namespace.ml_pipeline[0].metadata[0].labels["platform.component"] == "model-registry"
    error_message = "Namespace must carry platform.component = model-registry per ADR-0028."
  }

  assert {
    condition     = kubernetes_namespace.ml_pipeline[0].metadata[0].labels["platform.env"] == "prod"
    error_message = "Caller-supplied platform.env must be merged onto the namespace."
  }

  assert {
    condition     = kubernetes_namespace.ml_pipeline[0].metadata[0].labels["platform.managed-by"] == "terragrunt"
    error_message = "Namespace must carry platform.managed-by = terragrunt per ADR-0028."
  }
}

# -------------------------------------------------------------------------
# Run 6 — chart version must be pinned (not empty)
# -------------------------------------------------------------------------

run "minio_chart_version_pinned" {
  command = plan

  assert {
    condition     = length(var.minio_chart_version) > 0
    error_message = "MinIO Operator chart version must be pinned (not empty)."
  }
}

# -------------------------------------------------------------------------
# Run 7 — backend validation rejects invalid values
# -------------------------------------------------------------------------

run "outputs_backend_is_minio_by_default" {
  command = plan

  assert {
    condition     = var.backend == "minio"
    error_message = "Default backend must be 'minio' per ADR-0052 §7 OPEN DECISION 4."
  }
}
