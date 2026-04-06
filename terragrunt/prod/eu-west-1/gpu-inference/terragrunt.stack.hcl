# ---------------------------------------------------------------------------------------------------------------------
# GPU Inference Stack — Live Deployment (Prod)
# ---------------------------------------------------------------------------------------------------------------------
# Deploys the gpu-inference cluster infrastructure for prod eu-west-1.
# Phase 1: VPC with BGP-ready subnets and TGW Connect.
# Additional units will be added as subsequent issues are implemented.
# ---------------------------------------------------------------------------------------------------------------------

unit "gpu-inference-vpc" {
  source = "${get_repo_root()}/catalog/units/gpu-inference-vpc"
  path   = "gpu-inference-vpc"
}
