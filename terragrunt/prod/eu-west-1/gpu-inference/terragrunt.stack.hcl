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

unit "gpu-inference-tgw-connect" {
  source = "${get_repo_root()}/catalog/units/gpu-inference-tgw-connect"
  path   = "gpu-inference-tgw-connect"
}

unit "gpu-inference-dra" {
  source = "${get_repo_root()}/catalog/units/gpu-inference-dra"
  path   = "gpu-inference-dra"
}

unit "gpu-inference-volcano" {
  source = "${get_repo_root()}/catalog/units/gpu-inference-volcano"
  path   = "gpu-inference-volcano"
}

unit "gpu-inference-victoriametrics" {
  source = "${get_repo_root()}/catalog/units/gpu-inference-victoriametrics"
  path   = "gpu-inference-victoriametrics"
}

unit "gpu-inference-logging" {
  source = "${get_repo_root()}/catalog/units/gpu-inference-logging"
  path   = "gpu-inference-logging"
}

unit "gpu-inference-scheduling-policies" {
  source = "${get_repo_root()}/catalog/units/gpu-inference-scheduling-policies"
  path   = "gpu-inference-scheduling-policies"
}

unit "gpu-inference-dcgm" {
  source = "${get_repo_root()}/catalog/units/gpu-inference-dcgm"
  path   = "gpu-inference-dcgm"
}

unit "gpu-inference-vllm" {
  source = "${get_repo_root()}/catalog/units/gpu-inference-vllm"
  path   = "gpu-inference-vllm"
}

unit "gpu-inference-hpa" {
  source = "${get_repo_root()}/catalog/units/gpu-inference-hpa"
  path   = "gpu-inference-hpa"
}
