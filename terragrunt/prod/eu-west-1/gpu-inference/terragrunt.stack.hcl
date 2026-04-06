# ---------------------------------------------------------------------------------------------------------------------
# GPU Inference Stack — Live Deployment (Prod)
# ---------------------------------------------------------------------------------------------------------------------
# Deploys the gpu-inference cluster infrastructure for prod eu-west-1.
# Phase 1: VPC + EKS cluster foundation.
# Phase 2: Cilium v1.19 native routing + BGP Control Plane peering via TGW Connect.
# Phase 3: Cilium WireGuard transparent encryption + high-scale tuning for 5000 nodes.
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

unit "gpu-inference-cilium" {
  source = "${get_repo_root()}/catalog/units/gpu-inference-cilium"
  path   = "gpu-inference-cilium"
}

unit "gpu-inference-cilium-encryption" {
  source = "${get_repo_root()}/catalog/units/gpu-inference-cilium-encryption"
  path   = "gpu-inference-cilium-encryption"
}
unit "gpu-inference-gpu-operator" {
  source = "${get_repo_root()}/catalog/units/gpu-inference-gpu-operator"
  path   = "gpu-inference-gpu-operator"
}

unit "gpu-inference-kata-cc" {
  source = "${get_repo_root()}/catalog/units/gpu-inference-kata-cc"
  path   = "gpu-inference-kata-cc"
}
