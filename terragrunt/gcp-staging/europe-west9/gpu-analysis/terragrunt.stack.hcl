# ---------------------------------------------------------------------------------------------------------------------
# GCP GPU Video Analysis — Live Deployment (europe-west9)
# ---------------------------------------------------------------------------------------------------------------------
# Deploys the GCP GPU video analysis GKE infrastructure for staging in Paris.
# Environment-specific values come from project.hcl; region-specific from region.hcl.
#
# Usage:
#   terragrunt stack plan
#   terragrunt stack apply
# ---------------------------------------------------------------------------------------------------------------------

unit "gcp-gpu-vpc" {
  source = "${get_repo_root()}/catalog/units/gcp-gpu-vpc"
  path   = "gcp-gpu-vpc"
}

unit "gcp-gpu-gke" {
  source = "${get_repo_root()}/catalog/units/gcp-gpu-gke"
  path   = "gcp-gpu-gke"
}

unit "gcp-gpu-nodepools" {
  source = "${get_repo_root()}/catalog/units/gcp-gpu-nodepools"
  path   = "gcp-gpu-nodepools"
}
