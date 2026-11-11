# ---------------------------------------------------------------------------------------------------------------------
# Scaleway GPU Inference Stack Template
# ---------------------------------------------------------------------------------------------------------------------
# Composable Terragrunt stack for deploying a sovereign EU Scaleway Kapsule GPU inference platform.
#
# Dependency graph:
#   Phase 1 (parallel):
#     - scw-gpu-vpc             (Scaleway VPC + Private Network + Public Gateway NAT)
#     - scw-inference-platform  (Scaleway Object Storage S3 for LLM weights + Container Registry + Cockpit)
#   Phase 2:
#     - scw-kapsule-gpu         (Kapsule Dedicated cluster + Cilium CNI + L40S/H100/L4 GPU pools)
#   Phase 3 (parallel — reusing existing Helm/K8s modules from terraform/modules/):
#     - scw-argocd              (reuses terraform/modules/argocd -> GitOps fleet sync from apps/infra/*)
#     - scw-gpu-operator        (reuses terraform/modules/gke-gpu-operator -> NVIDIA GPU Operator)
#     - scw-gpu-dcgm            (reuses terraform/modules/gke-gpu-dcgm -> DCGM Exporter DaemonSet)
#     - scw-gpu-scheduling      (reuses terraform/modules/gke-gpu-scheduling -> Volcano/Kueue gang scheduler)
#     - scw-inference-gateway   (reuses terraform/modules/gke-inference-gateway -> Gateway API + InferencePool)
# ---------------------------------------------------------------------------------------------------------------------

unit "scw-gpu-vpc" {
  source = "${get_repo_root()}/catalog/units/scw-gpu-vpc"
  path   = "scw-gpu-vpc"
}

unit "scw-inference-platform" {
  source = "${get_repo_root()}/catalog/units/scw-inference-platform"
  path   = "scw-inference-platform"
}

unit "scw-kapsule-gpu" {
  source = "${get_repo_root()}/catalog/units/scw-kapsule-gpu"
  path   = "scw-kapsule-gpu"
}

unit "scw-argocd" {
  source = "${get_repo_root()}/catalog/units/scw-argocd"
  path   = "scw-argocd"
}

unit "scw-gpu-operator" {
  source = "${get_repo_root()}/catalog/units/scw-gpu-operator"
  path   = "scw-gpu-operator"
}

unit "scw-gpu-dcgm" {
  source = "${get_repo_root()}/catalog/units/scw-gpu-dcgm"
  path   = "scw-gpu-dcgm"
}

unit "scw-gpu-scheduling" {
  source = "${get_repo_root()}/catalog/units/scw-gpu-scheduling"
  path   = "scw-gpu-scheduling"
}

unit "scw-inference-gateway" {
  source = "${get_repo_root()}/catalog/units/scw-inference-gateway"
  path   = "scw-inference-gateway"
}
