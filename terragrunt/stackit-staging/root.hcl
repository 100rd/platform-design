# -----------------------------------------------------------------------------
# Root Terragrunt Configuration — STACKIT
# -----------------------------------------------------------------------------
# Gruntwork Stacks-style root config for STACKIT projects. Units in the catalog
# include this via:
#
#   include "root" {
#     path = find_in_parent_folders("root.hcl")
#   }
#
# Because this file lives inside stackit-staging/, find_in_parent_folders resolves
# here BEFORE the AWS root.hcl at terragrunt/root.hcl.
# -----------------------------------------------------------------------------

terragrunt_version_constraint = ">= 0.68.0"

locals {
  project_vars = read_terragrunt_config(find_in_parent_folders("project.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))
  common       = read_terragrunt_config(find_in_parent_folders("common.hcl"))
  versions     = read_terragrunt_config(find_in_parent_folders("versions.hcl"))

  project_id     = local.project_vars.locals.project_id
  project_name   = local.project_vars.locals.project_name
  environment    = local.project_vars.locals.environment
  stackit_region = local.region_vars.locals.stackit_region

  owner = try(local.project_vars.locals.owner, local.common.locals.default_owner)

  # Unified Platform Taxonomy (ADR-0028) — STACKIT plane
  platform_system     = try(local.project_vars.locals.platform_system, "ml-infrastructure")
  platform_component  = try(local.project_vars.locals.platform_component, "gpu-inference")
  platform_env        = local.environment
  platform_owner      = local.owner
  platform_managed_by = local.common.locals.platform_managed_by

  platform_labels = {
    platform_system     = local.platform_system
    platform_component  = local.platform_component
    platform_env        = local.platform_env
    platform_owner      = local.platform_owner
    platform_managed_by = local.platform_managed_by
  }
}

# -----------------------------------------------------------------------------
# Catalog: local infrastructure catalog
# -----------------------------------------------------------------------------
catalog {
  urls = ["${get_repo_root()}/catalog"]
}

# -----------------------------------------------------------------------------
# Remote State: STACKIT Object Storage (S3-compatible backend)
# -----------------------------------------------------------------------------
# Uses STACKIT's native S3-compatible endpoint (`https://object-storage.api.<region>.stackit.cloud`).
# -----------------------------------------------------------------------------
remote_state {
  backend = "s3"

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }

  config = {
    bucket = "tfstate-${local.project_name}-${local.stackit_region}"
    key    = "${local.environment}/${path_relative_to_include()}/terraform.tfstate"
    region = local.stackit_region

    endpoints = {
      s3 = "https://object-storage.api.${local.stackit_region}.stackit.cloud"
    }

    force_path_style            = true
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_s3_checksum            = true
  }
}

# -----------------------------------------------------------------------------
# Generate: STACKIT Provider
# -----------------------------------------------------------------------------
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"

  contents = <<-EOF
    provider "stackit" {
      default_region = "${local.stackit_region}"
    }
  EOF
}

# -----------------------------------------------------------------------------
# Generate: Terraform and Provider Version Constraints
# -----------------------------------------------------------------------------
generate "versions" {
  path      = "versions_override.tf"
  if_exists = "overwrite_terragrunt"

  contents = <<-EOF
    terraform {
      required_version = ">= 1.11.0"

      required_providers {
        stackit = {
          source  = "stackitcloud/stackit"
          version = "${local.versions.locals.provider_versions.stackit}"
        }
        helm = {
          source  = "hashicorp/helm"
          version = "${local.versions.locals.provider_versions.helm}"
        }
        kubernetes = {
          source  = "hashicorp/kubernetes"
          version = "${local.versions.locals.provider_versions.kubernetes}"
        }
      }
    }
  EOF
}

# -----------------------------------------------------------------------------
# Common Inputs: Passed to every module
# -----------------------------------------------------------------------------
inputs = merge(
  local.project_vars.locals,
  local.region_vars.locals,
  {
    labels = merge(
      {
        environment = local.environment
        managed-by  = "terragrunt"
        project     = local.project_name
        region      = local.stackit_region
      },
      local.platform_labels,
    )
  }
)
