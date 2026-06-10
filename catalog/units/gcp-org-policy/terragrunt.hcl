# ---------------------------------------------------------------------------------------------------------------------
# GCP Organization Policy — Catalog Unit (WS-E — security / compliance)
# ---------------------------------------------------------------------------------------------------------------------
# Binds the GCP org-policy constraint bundle (public-IP deny, CMEK enforcement,
# SA-key-creation deny, OS Login, Cloud SQL public-IP deny, GCS uniform/public-access,
# resource-location residency) to a resource-manager node — giving the GCP estate
# guardrail parity with the AWS scps + iam-baseline controls.
#
# No cluster dependency — this is a pure GCP resource-manager control-plane resource.
# Apply is GATED: an org-policy change is org-wide; never auto-apply (ADR-0040).
#
# Requires project.hcl with: org_policy_parent (organizations/ID | folders/ID |
#   projects/ID). If org_policy_parent is unset it falls back to scoping the policies
#   to the unit's own project_id (projects/<project_id>), the safe least-blast-radius
#   default for a non-prod sandbox.
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/terraform/modules/gcp-org-policy"
}

locals {
  project_vars = read_terragrunt_config(find_in_parent_folders("project.hcl"))

  environment = local.project_vars.locals.environment

  # Prefer an explicit org/folder parent when project.hcl provides one; otherwise
  # scope to this project only (least blast radius). org-policy binds to a
  # resource-manager node, not a billing account.
  org_policy_parent = try(
    local.project_vars.locals.org_policy_parent,
    "projects/${local.project_vars.locals.project_id}",
  )
}

# ---------------------------------------------------------------------------------------------------------------------
# MODULE INPUTS
# ---------------------------------------------------------------------------------------------------------------------

inputs = {
  parent = local.org_policy_parent

  # Deny-by-default posture. All constraints on; tune per-environment below.
  restrict_vm_external_ip          = true
  disable_sa_key_creation          = true
  disable_sa_key_upload            = true
  require_os_login                 = true
  restrict_public_ip_cloudsql      = true
  uniform_bucket_level_access      = true
  enforce_public_access_prevention = true

  # CMEK mandatory for the services the ML platform actually uses (GCS artifact store,
  # Cloud SQL MLflow backend, Compute/GKE GPU nodes, BigQuery feature data).
  enforce_cmek = [
    "bigquery.googleapis.com",
    "compute.googleapis.com",
    "storage.googleapis.com",
    "sqladmin.googleapis.com",
  ]

  # Data-residency: pin to US + EU location groups (mirrors AWS scps restrict_regions).
  # Tighten per data-classification before prod.
  allowed_resource_locations = [
    "in:us-locations",
    "in:eu-locations",
  ]

  # ADR-0028 GCP-plane labels (underscore keys; system = security for WS-E).
  # Recorded for provenance — org-policy resources are not labelable.
  labels = {
    platform_env   = local.environment
    platform_owner = "team-sec"
  }
}
