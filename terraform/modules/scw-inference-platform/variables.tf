variable "project_id" {
  description = "Scaleway project ID"
  type        = string
}

variable "region" {
  description = "Scaleway region (e.g. fr-par, nl-ams, pl-waw)"
  type        = string
  default     = "fr-par"
}

variable "models_bucket_name" {
  description = "Globally unique name for the Scaleway Object Storage bucket holding model weights & LoRA adapters"
  type        = string
}

variable "bucket_versioning_enabled" {
  description = "Enable S3 object versioning on the models/adapters bucket"
  type        = bool
  default     = true
}

variable "force_destroy_bucket" {
  description = "Allow deleting the bucket even when non-empty (only set true in dev/sandbox)"
  type        = bool
  default     = false
}

variable "enable_container_registry" {
  description = "Create a private Scaleway Container Registry namespace"
  type        = bool
  default     = true
}

variable "registry_namespace_name" {
  description = "Name of the Scaleway Container Registry namespace"
  type        = string
}

variable "enable_cockpit" {
  description = "Enable Scaleway Cockpit observability and provision a push token for DCGM/VictoriaMetrics"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags applied to the Scaleway Object Storage bucket"
  type        = map(string)
  default     = {}
}
