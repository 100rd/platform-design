# ---------------------------------------------------------------------------------------------------------------------
# OVHcloud Inference Platform Services Module
# ---------------------------------------------------------------------------------------------------------------------
# Provisions native OVHcloud companion services for the MKS GPU inference cluster:
#   1. OVHcloud Object Storage Bucket (S3-compatible, AES256 encrypted) for LLM weights & LoRA adapters
#   2. OVHcloud Managed Private Registry (Harbor) for custom vLLM / Triton / inference images
# ---------------------------------------------------------------------------------------------------------------------

resource "ovh_cloud_project_storage" "models" {
  service_name = var.service_name
  region_name  = var.s3_region
  name         = var.models_bucket_name

  versioning = {
    status = var.bucket_versioning_enabled ? "enabled" : "disabled"
  }

  encryption = {
    sse_algorithm = "AES256"
  }
}

resource "ovh_cloud_project_containerregistry" "inference" {
  count        = var.enable_container_registry ? 1 : 0
  service_name = var.service_name
  region       = var.s3_region
  name         = var.registry_name
  plan_id      = var.registry_plan_id
}
