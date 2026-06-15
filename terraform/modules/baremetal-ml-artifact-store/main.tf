# ---------------------------------------------------------------------------------------------------------------------
# baremetal-ml-artifact-store (ADR-0052 / WS-B)
# ---------------------------------------------------------------------------------------------------------------------
# Bare-metal analogue of ml-artifact-store (ADR-0037 D2).
# Provisions:
#   - ExternalSecret (ESO) materialising scoped S3 credentials from Vault KV v2
#     into a Kubernetes Secret consumed by MLflow + GH Actions.
#   - Kubernetes Namespace + ServiceAccount for MLflow (namespace created here if
#     not managed externally; gate via var.enabled).
#   - Optional: MinIO Operator Helm release (if var.minio_deploy_in_cluster = true).
#
# The S3 bucket itself (MinIO bucket or Ceph-RGW bucket) is created out-of-band:
#   - MinIO: via `mc mb` in the MinIO tenant init Job (or pre-existing UK-DC pool).
#   - Ceph-RGW: via CephObjectStoreUser / radosgw-admin (owned by baremetal-rook-ceph WS-A).
# This module wires the credential binding so the ML plane can access the bucket.
#
# ADR-0028: K8s-plane labels use dotted keys (platform.system = ml-pipeline).
# ADR-0037: Airflow/MLflow orchestrator/registry design; only the storage substrate changes.
# ADR-0052: MinIO (default) or Ceph-RGW S3 endpoint; UK data-residency — no external S3.
# ADR-0049: Fully isolated UK ML control plane.
#
# APPLY-GATED: var.enabled defaults to false — no resource is created in plan-only runs.
# Set enabled = true ONLY after explicit human review + blast-radius approval.
# ---------------------------------------------------------------------------------------------------------------------

locals {
  # ADR-0028 K8s-plane baseline labels (dotted keys) merged with caller overrides.
  platform_labels = merge(
    {
      "platform.system"     = "ml-pipeline"
      "platform.component"  = "model-registry"
      "platform.managed-by" = "terragrunt"
    },
    var.platform_labels,
  )
}

# ---------------------------------------------------------------------------------------------------------------------
# Namespace — ml-pipeline (gated; may already exist if Airflow deploys first).
# Carries ADR-0028 labels so all enclosed resources inherit the system boundary.
# ---------------------------------------------------------------------------------------------------------------------

resource "kubernetes_namespace" "ml_pipeline" {
  count = var.enabled ? 1 : 0

  metadata {
    name   = var.namespace
    labels = local.platform_labels

    annotations = {
      "platform.adr"         = "ADR-0037,ADR-0052"
      "platform.description" = "ML pipeline namespace — Airflow + MLflow + artifact store (bare metal)"
    }
  }

  lifecycle {
    # Namespace likely shared with Airflow; ignore if already exists.
    ignore_changes = [metadata[0].annotations, metadata[0].labels]
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# ServiceAccount — mlflow
# ESO's ExternalSecret references this SA in the ownership chain.
# ADR-0028 labels carried on the SA so Gatekeeper/Kyverno can audit.
# ---------------------------------------------------------------------------------------------------------------------

resource "kubernetes_service_account" "mlflow" {
  count = var.enabled ? 1 : 0

  metadata {
    name      = var.kubernetes_service_account
    namespace = var.namespace
    labels    = local.platform_labels

    annotations = {
      # Signal for tools that this SA is NOT a GCP WI SA; credentials come from ESO/Vault.
      "platform.credential-source" = "vault-eso"
    }
  }

  depends_on = [kubernetes_namespace.ml_pipeline]
}

# ---------------------------------------------------------------------------------------------------------------------
# ExternalSecret — S3 credentials for the MLflow artifact store
# Materialises: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, MLFLOW_S3_ENDPOINT_URL
# into the Kubernetes Secret var.secret_name inside the ml-pipeline namespace.
# Vault KV v2 path: var.vault_path (never hardcoded here — ADR security invariant).
# ADR-0008 (ESO) + ADR-0052 (MinIO/Ceph-RGW substrate).
# ---------------------------------------------------------------------------------------------------------------------

resource "kubernetes_manifest" "mlflow_s3_externalsecret" {
  count = var.enabled ? 1 : 0

  manifest = {
    apiVersion = "external-secrets.io/v1"
    kind       = "ExternalSecret"
    metadata = {
      name      = "mlflow-s3-credentials"
      namespace = var.namespace
      labels    = local.platform_labels
      annotations = {
        "platform.adr" = "ADR-0008,ADR-0052"
      }
    }
    spec = {
      refreshInterval = "1h"
      secretStoreRef = {
        name = var.cluster_secret_store_name
        kind = "ClusterSecretStore"
      }
      target = {
        name           = var.secret_name
        creationPolicy = "Owner"
      }
      data = [
        {
          secretKey = "AWS_ACCESS_KEY_ID"
          remoteRef = {
            key      = var.vault_path
            property = "access_key"
          }
        },
        {
          secretKey = "AWS_SECRET_ACCESS_KEY"
          remoteRef = {
            key      = var.vault_path
            property = "secret_key"
          }
        },
        {
          secretKey = "MLFLOW_S3_ENDPOINT_URL"
          remoteRef = {
            key      = var.vault_path
            property = "endpoint_url"
          }
        },
      ]
    }
  }

  depends_on = [kubernetes_namespace.ml_pipeline]
}

# ---------------------------------------------------------------------------------------------------------------------
# Optional MinIO Operator Helm release
# Only deployed if var.minio_deploy_in_cluster = true AND var.backend = "minio".
# The UK DC already lists MinIO pools; in practice this is a shared instance, so
# minio_deploy_in_cluster defaults to false (connect to an existing MinIO).
# When Ceph-RGW is the substrate (backend = "ceph-rgw"), MinIO Operator is not deployed.
# ---------------------------------------------------------------------------------------------------------------------

resource "helm_release" "minio_operator" {
  count = var.enabled && var.minio_deploy_in_cluster && var.backend == "minio" ? 1 : 0

  name       = "minio-operator"
  repository = var.minio_chart_repository
  chart      = "operator"
  version    = var.minio_chart_version
  namespace  = var.minio_namespace
  timeout    = var.minio_helm_timeout

  create_namespace = true

  values = [
    yamlencode({
      operator = {
        replicaCount = 1
        resources = {
          requests = { cpu = "200m", memory = "256Mi" }
          limits   = { cpu = "500m", memory = "512Mi" }
        }
        # ADR-0028 labels on operator pods
        podLabels = local.platform_labels
      }
      # Tenant is provisioned separately (out of scope of this module).
      # This chart installs the Operator only.
      tenants = {}
    })
  ]

  # ADR-0028: chart-level annotations for ArgoCD label propagation
  set {
    name  = "operator.podAnnotations.platform\\.system"
    value = "ml-pipeline"
  }
}
