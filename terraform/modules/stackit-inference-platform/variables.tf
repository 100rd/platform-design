variable "project_id" {
  description = "STACKIT project UUID"
  type        = string
}

variable "region" {
  description = "STACKIT region (e.g. eu01)"
  type        = string
  default     = "eu01"
}

variable "models_bucket_name" {
  description = "Globally unique S3 bucket name for LLM weights & LoRA adapters"
  type        = string
}

variable "enable_observability" {
  description = "Provision a STACKIT Observability (Argus) instance for SKE & GPU metrics"
  type        = bool
  default     = true
}

variable "observability_plan_name" {
  description = "Service plan for STACKIT Observability (Argus)"
  type        = string
  default     = "Observability-Monitoring-Medium-EU01"
}
