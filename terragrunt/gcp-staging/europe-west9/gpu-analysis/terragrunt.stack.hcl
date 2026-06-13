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

unit "gke-gpu-operator" {
  source = "${get_repo_root()}/catalog/units/gke-gpu-operator"
  path   = "gke-gpu-operator"
}

unit "gke-gpu-dcgm" {
  source = "${get_repo_root()}/catalog/units/gke-gpu-dcgm"
  path   = "gke-gpu-dcgm"
}

unit "gke-gpu-scheduling" {
  source = "${get_repo_root()}/catalog/units/gke-gpu-scheduling"
  path   = "gke-gpu-scheduling"
}

unit "gcp-billing-budget" {
  source = "${get_repo_root()}/catalog/units/gcp-billing-budget"
  path   = "gcp-billing-budget"
}

# ---------------------------------------------------------------------------------------------------------------------
# ADR-0042 — GPU inference networking & serving uplift (all gated OFF by default via
# gpu_analysis_config flags; enabling each is apply-gated).
# ---------------------------------------------------------------------------------------------------------------------

unit "gcp-cloud-armor" {
  source = "${get_repo_root()}/catalog/units/gcp-cloud-armor"
  path   = "gcp-cloud-armor"
}

unit "gke-gpu-dranet" {
  source = "${get_repo_root()}/catalog/units/gke-gpu-dranet"
  path   = "gke-gpu-dranet"
}

unit "gke-gpu-fabric" {
  source = "${get_repo_root()}/catalog/units/gke-gpu-fabric"
  path   = "gke-gpu-fabric"
}

unit "gke-inference-gateway" {
  source = "${get_repo_root()}/catalog/units/gke-inference-gateway"
  path   = "gke-inference-gateway"
}
