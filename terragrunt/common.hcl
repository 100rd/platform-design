# -----------------------------------------------------------------------------
# Shared locals + tag conventions
# -----------------------------------------------------------------------------
# Repo-wide constants surfaced as Terragrunt locals so unit files don't
# hard-code values. Consumed by `root.hcl` and (optionally) by individual
# units that need access to project metadata or canonical tag sets.
#
# Mirrors infra `common.hcl`. Read via:
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

  # ---- Unified Platform Taxonomy (ADR-0028) ----
  # The five core platform:* tag keys that link the AWS infrastructure plane
  # (these tags) to the Kubernetes workload plane (platform.* labels). These
  # keys MUST match the K8s labels exactly (casing/format) so Prometheus/Grafana
  # joins, FinOps allocation, and incident response correlation work.
  #
  #   platform:system     -> logical service boundary    (auth, payment, ...)
  #   platform:component  -> architectural tier/role      (database, cache, ...)
  #   platform:env        -> deployment environment       (driven by account.hcl)
  #   platform:owner      -> responsible engineering team (driven by account.hcl)
  #   platform:managed-by -> orchestrating tool           (terragrunt on AWS plane)
  #
  # `system` and `component` are overridable repo-wide defaults: most units
  # belong to no single logical system and should be overridden per-unit via the
  # unit's `tags` input. `env`, `owner`, and `managed-by` are derived in root.hcl
  # from account context so they cannot drift.
  platform_managed_by = "terragrunt"

  # Sensible overridable defaults. A unit that hosts a specific logical service
  # (e.g. the `auth` RDS/S3 stack) sets these via its own `tags` input, which the
  # root merges on top of these defaults (unit wins).
  default_platform_system    = "shared"
  default_platform_component = "shared"

  # ---- Region catalog ----
  # Canonical 4-region EU footprint. Used by region.hcl files for short codes.
  region_short_codes = {
    "eu-west-1"    = "euw1"
    "eu-west-2"    = "euw2"
    "eu-west-3"    = "euw3"
    "eu-central-1" = "euc1"
  }
}
