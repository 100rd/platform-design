# ---------------------------------------------------------------------------------------------------------------------
# Inputs for the gcp-org-policy module (WS-E — security / compliance).
# ---------------------------------------------------------------------------------------------------------------------

variable "parent" {
  description = <<-EOT
    The resource-manager node the org policies bind to, in `google_org_policy_policy`
    parent form: `organizations/{ORG_ID}`, `folders/{FOLDER_ID}`, or
    `projects/{PROJECT_ID}`. Binding at the organization or a top-level folder gives
    org-wide guardrails; binding at a project scopes them to a single GCP project.
  EOT
  type        = string

  validation {
    condition     = can(regex("^(organizations|folders|projects)/[^/]+$", var.parent))
    error_message = "parent must be one of organizations/ID, folders/ID, or projects/ID."
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# Boolean constraint toggles — each maps to a CIS / SOC2-relevant GCP org-policy
# constraint. All default ON (deny-by-default posture); set false to carve a
# constraint out (e.g. during a staged rollout).
# ---------------------------------------------------------------------------------------------------------------------

variable "restrict_vm_external_ip" {
  description = "Enforce constraints/compute.vmExternalIpAccess (deny public IPs on Compute/GKE VMs unless explicitly allow-listed). SOC2 CC6.6."
  type        = bool
  default     = true
}

variable "vm_external_ip_allowed_projects" {
  description = "When restrict_vm_external_ip is true, allow-list values for compute.vmExternalIpAccess (e.g. projects/ID/zones/.../instances/...). Empty = deny all external IPs."
  type        = list(string)
  default     = []
  nullable    = false
}

variable "disable_sa_key_creation" {
  description = "Enforce constraints/iam.disableServiceAccountKeyCreation (block long-lived SA keys; forces Workload Identity / WIF). SOC2 CC6.1 / CC6.3."
  type        = bool
  default     = true
}

variable "disable_sa_key_upload" {
  description = "Enforce constraints/iam.disableServiceAccountKeyUpload (block uploading externally-generated SA keys). Complements disable_sa_key_creation."
  type        = bool
  default     = true
}

variable "require_os_login" {
  description = "Enforce constraints/compute.requireOsLogin (centralised IAM-managed SSH instead of project SSH keys). SOC2 CC6.1."
  type        = bool
  default     = true
}

variable "restrict_public_ip_cloudsql" {
  description = "Enforce constraints/sql.restrictPublicIp (Cloud SQL — the MLflow backend store in ADR-0037 — may not have a public IP). SOC2 CC6.6."
  type        = bool
  default     = true
}

variable "uniform_bucket_level_access" {
  description = "Enforce constraints/storage.uniformBucketLevelAccess (GCS — MLflow artifact store — must use uniform bucket-level IAM, no per-object ACLs). SOC2 CC6.1 / CC6.3."
  type        = bool
  default     = true
}

variable "enforce_public_access_prevention" {
  description = "Enforce constraints/storage.publicAccessPrevention (no public GCS buckets org-wide). SOC2 CC6.6 — parity with the AWS S3 account public-access block in iam-baseline / scps deny_s3_public."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------------------------------------------------
# CMEK enforcement — list constraint requiring customer-managed encryption keys.
# ---------------------------------------------------------------------------------------------------------------------

variable "enforce_cmek" {
  description = "Services that may only create resources with customer-managed keys, via constraints/gcp.restrictNonCmekServices. SOC2 CC6.1 — encryption at rest. Empty list = disabled."
  type        = list(string)
  default = [
    "bigquery.googleapis.com",
    "compute.googleapis.com",
    "storage.googleapis.com",
    "sqladmin.googleapis.com",
  ]
  nullable = false
}

# ---------------------------------------------------------------------------------------------------------------------
# Resource location restriction — list constraint pinning resources to allowed regions.
# ---------------------------------------------------------------------------------------------------------------------

variable "allowed_resource_locations" {
  description = "Enforce constraints/gcp.resourceLocations (data-residency guardrail; mirrors the AWS scps restrict_regions control). Values are location group/value forms, e.g. in:eu-locations, in:us-locations. Empty = disabled."
  type        = list(string)
  default     = []
  nullable    = false
}

# ---------------------------------------------------------------------------------------------------------------------
# ADR-0028 labels. NOTE: google_org_policy_policy has NO labels argument (it is an
# org-policy binding, not a labelable resource), so — exactly like the
# gcp-billing-budget module documents for google_billing_budget — the ADR-0028
# taxonomy is asserted via this variable for catalog/test provenance and is the
# contract a reviewer greps for. Keys use the GCP underscore spelling.
# ---------------------------------------------------------------------------------------------------------------------

variable "labels" {
  description = "ADR-0028 platform taxonomy (GCP underscore keys, e.g. platform_system = security). Recorded for provenance; org-policy resources are not labelable, so these are not applied to a GCP resource here."
  type        = map(string)
  default     = {}
  nullable    = false
}
