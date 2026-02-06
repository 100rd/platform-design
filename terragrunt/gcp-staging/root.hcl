# -----------------------------------------------------------------------------
# Root Terragrunt Configuration — GCP
# -----------------------------------------------------------------------------
# Gruntwork Stacks-style root config for GCP projects. Units in the catalog
# include this via:
#
#   include "root" {
#     path = find_in_parent_folders("root.hcl")
#   }
#
# Because this file lives inside gcp-staging/, find_in_parent_folders resolves
# here BEFORE the AWS root.hcl at terragrunt/root.hcl.
#
# Hierarchy files expected in the directory tree:
#   project.hcl  - defines project_id, project_name, environment, sizing
#   region.hcl   - defines gcp_region, region_short, zones
# -----------------------------------------------------------------------------

terragrunt_version_constraint = ">= 0.68.0"

# -----------------------------------------------------------------------------
# Locals: Read hierarchy config files
# -----------------------------------------------------------------------------
locals {
  project_vars = read_terragrunt_config(find_in_parent_folders("project.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  project_id   = local.project_vars.locals.project_id
  project_name = local.project_vars.locals.project_name
  gcp_region   = local.region_vars.locals.gcp_region
  environment  = local.project_vars.locals.environment
}

# -----------------------------------------------------------------------------
# Catalog: local infrastructure catalog
# -----------------------------------------------------------------------------
catalog {
  urls = ["${get_repo_root()}/catalog"]
}

# -----------------------------------------------------------------------------
# Remote State: GCS backend
# -----------------------------------------------------------------------------
remote_state {
  backend = "gcs"

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }

  config = {
    bucket = "tfstate-${local.project_id}-${local.gcp_region}"
    prefix = "${local.environment}/${path_relative_to_include()}/terraform.tfstate"

    project  = local.project_id
    location = local.gcp_region
  }
}

# -----------------------------------------------------------------------------
# Generate: Google Provider
# -----------------------------------------------------------------------------
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"

  contents = <<-EOF
    provider "google" {
      project = "${local.project_id}"
      region  = "${local.gcp_region}"

      default_labels = {
        environment = "${local.environment}"
        managed-by  = "terragrunt"
        project     = "${local.project_id}"
        region      = "${local.gcp_region}"
      }
    }

    provider "google-beta" {
      project = "${local.project_id}"
      region  = "${local.gcp_region}"

      default_labels = {
        environment = "${local.environment}"
        managed-by  = "terragrunt"
        project     = "${local.project_id}"
        region      = "${local.gcp_region}"
      }
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
        google = {
          source  = "hashicorp/google"
          version = "~> 6.0"
        }
        google-beta = {
          source  = "hashicorp/google-beta"
          version = "~> 6.0"
        }
      }
    }
  EOF
}

# -----------------------------------------------------------------------------
# Retry configuration for transient GCP errors
# -----------------------------------------------------------------------------
retry_max_attempts       = 3
retry_sleep_interval_sec = 5

retryable_errors = [
  "(?s).*Error creating.*",
  "(?s).*RequestError: send request failed.*",
  "(?s).*connection reset by peer.*",
  "(?s).*googleapi: Error 429.*",
  "(?s).*googleapi: Error 503.*",
]

# -----------------------------------------------------------------------------
# Common Inputs: Passed to every module
# -----------------------------------------------------------------------------
inputs = merge(
  local.project_vars.locals,
  local.region_vars.locals,
  {
    labels = {
      environment = local.environment
      managed-by  = "terragrunt"
      project     = local.project_id
      region      = local.gcp_region
    }
  }
)
