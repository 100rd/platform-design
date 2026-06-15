# ---------------------------------------------------------------------------------------------------------------------
# baremetal-ml-artifact-store — Variables (ADR-0052 / WS-B)
# ---------------------------------------------------------------------------------------------------------------------
# Bare-metal analogue of ml-artifact-store. Provisions a MinIO or Ceph-RGW S3
# bucket + a scoped S3 credential (via Vault / ESO) for MLflow artifact storage.
# The S3 API is endpoint-agnostic: MLflow and the GH Actions pipeline only see
# an MLFLOW_S3_ENDPOINT_URL pointing at the in-cluster MinIO or Ceph-RGW service.
# No GCP/AWS credentials — everything is in-cluster.
#
# ADR-0028: K8s-plane labels use dotted keys (platform.system).
# ADR-0037: reused orchestrator/registry design; only the substrate changes.
# ADR-0052: MinIO is the default; Ceph-RGW is the alternative (same S3 API).
# ---------------------------------------------------------------------------------------------------------------------

# -------------------------------------------------------------------------
# Feature gate (apply-gated — default OFF in mock repo)
# -------------------------------------------------------------------------

variable "enabled" {
  description = "Master gate. Set to false to skip all resource creation (apply-gated / mock-repo default)."
  type        = bool
  default     = false
}

# -------------------------------------------------------------------------
# Object-store backend
# -------------------------------------------------------------------------

variable "backend" {
  description = "S3-compatible backend to use. Allowed: 'minio' (default, per ADR-0052 §7 OPEN DECISION 4) or 'ceph-rgw'."
  type        = string
  default     = "minio"

  validation {
    condition     = contains(["minio", "ceph-rgw"], var.backend)
    error_message = "backend must be 'minio' or 'ceph-rgw'."
  }
}

variable "s3_endpoint_url" {
  description = "S3-compatible endpoint URL for the artifact store (e.g. http://minio.minio-system.svc.cluster.local:9000). Must NOT contain credentials."
  type        = string
  default     = "http://minio.minio-system.svc.cluster.local:9000"
}

variable "bucket_name" {
  description = "Name of the S3/MinIO/RGW bucket used as the MLflow artifact store."
  type        = string
  default     = "mlflow-artifacts"
}

# -------------------------------------------------------------------------
# Vault / ESO credential source
# -------------------------------------------------------------------------

variable "vault_path" {
  description = "Vault KV v2 path that holds the scoped S3 access/secret key for the MLflow artifact store. Never hardcode credentials here."
  type        = string
  default     = "secret/data/ml-pipeline/mlflow-s3-credentials"
}

variable "cluster_secret_store_name" {
  description = "Name of the ESO ClusterSecretStore that points at the in-cluster Vault instance (ADR-0008)."
  type        = string
  default     = "vault-cluster-store"
}

# -------------------------------------------------------------------------
# Kubernetes target (for ExternalSecret + ServiceAccount)
# -------------------------------------------------------------------------

variable "namespace" {
  description = "Kubernetes namespace where MLflow runs and where the S3 credential Secret is materialised."
  type        = string
  default     = "ml-pipeline"
}

variable "kubernetes_service_account" {
  description = "Kubernetes ServiceAccount name for MLflow pods. Annotated for ESO binding."
  type        = string
  default     = "mlflow"
}

variable "secret_name" {
  description = "Name of the Kubernetes Secret that ESO will create for the S3 credentials (access key + secret key + endpoint URL)."
  type        = string
  default     = "mlflow-s3-credentials"
}

# -------------------------------------------------------------------------
# MinIO / Helm (only used when backend = 'minio' and minio_deploy_in_cluster = true)
# -------------------------------------------------------------------------

variable "minio_deploy_in_cluster" {
  description = "Deploy the MinIO tenant via the MinIO Operator Helm chart (in-cluster). Set false when MinIO is already deployed (shared instance or Ceph-RGW)."
  type        = bool
  default     = false
}

variable "minio_chart_version" {
  description = "Pinned MinIO Operator Helm chart version."
  type        = string
  default     = "6.0.4"
}

variable "minio_chart_repository" {
  description = "Helm repository URL for the MinIO Operator chart."
  type        = string
  default     = "https://operator.min.io"
}

variable "minio_namespace" {
  description = "Namespace for the MinIO Operator (if deploying in-cluster)."
  type        = string
  default     = "minio-system"
}

variable "minio_storage_size" {
  description = "PVC size for each MinIO volume. Requires a StorageClass backed by Rook-Ceph RBD or local NVMe."
  type        = string
  default     = "500Gi"
}

variable "minio_storage_class" {
  description = "StorageClass for MinIO PVCs. Should be 'rook-ceph-block' when Rook-Ceph is the substrate (ADR-0052)."
  type        = string
  default     = "rook-ceph-block"
}

variable "minio_helm_timeout" {
  description = "Helm release timeout in seconds for the MinIO Operator chart."
  type        = number
  default     = 300
}

# -------------------------------------------------------------------------
# Lifecycle / retention
# -------------------------------------------------------------------------

variable "retention_days" {
  description = "Soft-delete / lifecycle retention in days. Configured as an ILM rule via a Kubernetes Job post-hook (MinIO mc) or Ceph-RGW lifecycle API."
  type        = number
  default     = 365

  validation {
    condition     = var.retention_days >= 0
    error_message = "retention_days must be >= 0."
  }
}

# -------------------------------------------------------------------------
# ADR-0028 labels — Kubernetes-plane spelling (dotted keys)
# -------------------------------------------------------------------------

variable "platform_labels" {
  description = <<-EOT
    ADR-0028 platform labels. Required caller-supplied keys:
      platform.env   (e.g. "staging", "prod")
      platform.owner (e.g. "team-ml")
    Merged with baseline: platform.system=ml-pipeline, platform.component=model-registry,
    platform.managed-by=terragrunt.
  EOT
  type        = map(string)
  default = {
    "platform.env"   = "staging"
    "platform.owner" = "team-ml"
  }
}
