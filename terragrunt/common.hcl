# -----------------------------------------------------------------------------
# Shared locals + tag conventions
# -----------------------------------------------------------------------------
# Repo-wide constants surfaced as Terragrunt locals so unit files don't
# hard-code values. Consumed by `root.hcl` and (optionally) by individual
# units that need access to project metadata or canonical tag sets.
#
# Mirrors qbiq-ai/infra `common.hcl`. Read via:
#   locals {
#     common = read_terragrunt_config(find_in_parent_folders("common.hcl"))
#   }
# -----------------------------------------------------------------------------

locals {
  # ---- Project metadata ----
  project_name = "platform-design"
  org_name     = "100rd"
  repository   = "100rd/platform-design"

  # Default cost-allocation owners. Account / unit overrides win.
  default_owner       = "platform-team"
  default_cost_center = "platform"

  # ---- Tag schema ----
  # Tags applied to every AWS resource. Per-unit overrides go through the
  # `tags` input on the unit (the root merges `tags` from inputs into
  # provider default_tags).
  managed_by_tag_value = "terragrunt"

  # Compliance frameworks tracked in tags for resource-level reporting.
  default_compliance_frameworks = "pci-dss,soc2,iso27001"

  # ---- Region catalog ----
  # Canonical 4-region EU footprint. Used by region.hcl files for short codes.
  region_short_codes = {
    "eu-west-1"    = "euw1"
    "eu-west-2"    = "euw2"
    "eu-west-3"    = "euw3"
    "eu-central-1" = "euc1"
  }
}
