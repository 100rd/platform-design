# ---------------------------------------------------------------------------------------------------------------------
# GCP GPU Video Analysis Stack Template
# ---------------------------------------------------------------------------------------------------------------------
# Composable stack that deploys GCP GPU video analysis GKE infrastructure:
#   gcp-gpu-vpc → gcp-gpu-gke → gcp-gpu-nodepools
#
# GCP is significantly simpler than AWS (3 units vs 7):
#   - GKE Dataplane V2 = Cilium built-in (no separate cilium unit)
#   - GKE native node pools = no Karpenter (no karpenter-iam/controller/nodepools)
#   - Zone affinity = built into node pool config (no placement-group unit)
#
# Optimized for real-time video analysis: GPU instances (L4/T4), single-zone
# pinning for GPU locality, mixed on-demand/spot capacity.
#
# Usage (from live tree):
#   cd terragrunt/gcp-staging/europe-west9/gpu-analysis
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
