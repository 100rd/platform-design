# ---------------------------------------------------------------------------------------------------------------------
# STACKIT Inference Platform Services Module
# ---------------------------------------------------------------------------------------------------------------------
# Provisions native STACKIT companion services for the SKE GPU inference cluster:
#   1. STACKIT Object Storage Bucket (S3-compatible) for LLM weights, checkpoints, and LoRA adapters
#   2. STACKIT Observability / Argus Instance (managed Prometheus + Thanos + Loki + Grafana)
# ---------------------------------------------------------------------------------------------------------------------

resource "stackit_objectstorage_bucket" "models" {
  project_id = var.project_id
  name       = var.models_bucket_name
  region     = var.region
}

resource "stackit_observability_instance" "this" {
  count      = var.enable_observability ? 1 : 0
  project_id = var.project_id
  name       = "${var.models_bucket_name}-obs"
  plan_name  = var.observability_plan_name
}
