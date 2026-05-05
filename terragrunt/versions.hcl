# -----------------------------------------------------------------------------
# Tool & Provider Version Pins
# -----------------------------------------------------------------------------
# Single source of truth for pinned versions across the platform-design repo.
# Mirrors qbiq-ai/infra `versions.hcl`. Consumed by:
#   - root.hcl   (terraform/terragrunt version constraints + provider blocks)
#   - CI checks  (matrix versions)
#   - Tooling    (.terraform-version, .terragrunt-version — see issue #174)
#
# Usage from a unit:
#   include "root" { path = find_in_parent_folders("root.hcl") }
#   locals {
#     versions = read_terragrunt_config(find_in_parent_folders("versions.hcl"))
#   }
#
# Bump policy:
#   - Patch / minor: PR with `chore: bump <tool> to <version>` + green CI on a
#     non-prod env first.
#   - Major: ADR required (see docs/decisions/) + multi-env soak.
# -----------------------------------------------------------------------------

locals {
  # ---- Tool versions ----
  terraform_version  = "1.14.8"
  terragrunt_version = "0.99.5"

  # Pretty constraint forms (consumed by `required_version` and `terragrunt_version_constraint`)
  terraform_version_constraint  = "= ${local.terraform_version}"
  terragrunt_version_constraint = "= ${local.terragrunt_version}"

  # ---- Provider versions ----
  # `~> X.Y` allows patch updates; pin tighter via PR if drift becomes an issue.
  provider_versions = {
    aws        = "~> 6.0"
    helm       = "~> 2.12"
    kubernetes = "~> 2.30"
    null       = "~> 3.2"
    random     = "~> 3.6"
    tls        = "~> 4.0"
  }
}
