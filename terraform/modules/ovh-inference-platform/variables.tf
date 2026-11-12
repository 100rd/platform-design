variable "service_name" {
  description = "OVHcloud Public Cloud Project ID (service_name)"
  type        = string
}

variable "s3_region" {
  description = "OVHcloud Object Storage / Harbor region (e.g. GRA)"
  type        = string
  default     = "GRA"
}

variable "models_bucket_name" {
  description = "Name of the OVHcloud S3 Object Storage bucket for LLM weights & LoRA adapters"
  type        = string
}

variable "bucket_versioning_enabled" {
  description = "Enable S3 object versioning on the models bucket"
  type        = bool
  default     = true
}

variable "enable_container_registry" {
  description = "Provision an OVHcloud Managed Private Registry (Harbor)"
  type        = bool
  default     = true
}

variable "registry_name" {
  description = "Name of the OVHcloud Managed Private Registry"
  type        = string
}

variable "registry_plan_id" {
  description = "Plan ID for the Managed Private Registry (SMALL, MEDIUM, LARGE)"
  type        = string
  default     = "SMALL"
}
