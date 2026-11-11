# ---------------------------------------------------------------------------------------------------------------------
# Scaleway Inference Platform Services Module
# ---------------------------------------------------------------------------------------------------------------------
# Provisions native Scaleway companion services for the GPU inference cluster:
#   1. Object Storage Bucket (S3-compatible, zero intra-region egress) for LLM weights & LoRA adapters
#   2. Container Registry Namespace (private OCI registry for custom vLLM / inference images)
#   3. Scaleway Cockpit (managed Prometheus + Loki + Grafana observability + remote-write token)
# ---------------------------------------------------------------------------------------------------------------------

resource "scaleway_object_bucket" "models" {
  project_id    = var.project_id
  name          = var.models_bucket_name
  region        = var.region
  force_destroy = var.force_destroy_bucket
  tags          = var.tags

  versioning {
    enabled = var.bucket_versioning_enabled
  }

  lifecycle_rule {
    id                                     = "abort-incomplete-multipart-uploads"
    enabled                                = true
    abort_incomplete_multipart_upload_days = 7
  }
}

resource "scaleway_object_bucket_acl" "models" {
  project_id = var.project_id
  bucket     = scaleway_object_bucket.models.name
  region     = var.region
  acl        = "private"
}

resource "scaleway_registry_namespace" "inference" {
  count       = var.enable_container_registry ? 1 : 0
  project_id  = var.project_id
  name        = var.registry_namespace_name
  region      = var.region
  description = "Private OCI registry for GPU inference images (vLLM, Triton, LoRA adapters)"
  is_public   = false
}

resource "scaleway_cockpit" "this" {
  count      = var.enable_cockpit ? 1 : 0
  project_id = var.project_id
}

resource "scaleway_cockpit_token" "gpu_metrics" {
  count      = var.enable_cockpit ? 1 : 0
  project_id = scaleway_cockpit.this[0].project_id
  name       = "${var.models_bucket_name}-cockpit-exporter"

  scopes {
    query_metrics = true
    write_metrics = true
    query_logs    = true
    write_logs    = true
  }
}
