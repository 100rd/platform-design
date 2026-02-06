# ---------------------------------------------------------------------------------------------------------------------
# GCP GPU VPC — Catalog Unit
# ---------------------------------------------------------------------------------------------------------------------
# Creates a custom-mode GCP VPC with subnet, Cloud Router, and Cloud NAT for the
# GPU video analysis GKE cluster. The subnet includes secondary IP ranges for
# GKE pods and services, and private Google API access is enabled.
#
# Requires project.hcl with: project_id, environment
# Requires region.hcl with: gcp_region
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/terraform/modules/gcp-gpu-vpc"
}

locals {
  project_vars = read_terragrunt_config(find_in_parent_folders("project.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  gcp_project_id = local.project_vars.locals.project_id
  environment    = local.project_vars.locals.environment
  gcp_region     = local.region_vars.locals.gcp_region
}

# ---------------------------------------------------------------------------------------------------------------------
# MODULE INPUTS
# ---------------------------------------------------------------------------------------------------------------------

inputs = {
  project_id   = local.gcp_project_id
  network_name = "${local.environment}-${local.gcp_region}-gcp-gpu-analysis"
  region       = local.gcp_region
  subnet_cidr  = "10.200.0.0/16"
  environment  = local.environment

  labels = {
    environment  = local.environment
    managed-by   = "terragrunt"
    cluster-role = "gpu-analysis"
  }
}
