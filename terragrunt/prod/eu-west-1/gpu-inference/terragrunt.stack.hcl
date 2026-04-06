# ---------------------------------------------------------------------------------------------------------------------
# GPU Inference Stack — Live Deployment (Prod)
# ---------------------------------------------------------------------------------------------------------------------
# Deploys the gpu-inference cluster infrastructure for prod eu-west-1.
# Phase 1: VPC + EKS cluster foundation.
# Additional units will be added as subsequent issues are implemented.
# ---------------------------------------------------------------------------------------------------------------------

unit "gpu-inference-vpc" {
  source = "${get_repo_root()}/catalog/units/gpu-inference-vpc"
  path   = "gpu-inference-vpc"
}

unit "gpu-inference-eks" {
  source = "${get_repo_root()}/catalog/units/gpu-inference-eks"
  path   = "gpu-inference-eks"
}

unit "gpu-inference-node-tuning" {
  source = "${get_repo_root()}/catalog/units/gpu-inference-node-tuning"
  path   = "gpu-inference-node-tuning"
}
