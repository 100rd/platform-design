# ---------------------------------------------------------------------------------------------------------------------
# STACKIT GPU Inference Stack Template
# ---------------------------------------------------------------------------------------------------------------------
# Composable Terragrunt stack for deploying a sovereign EU STACKIT SKE GPU inference platform.
#
# Dependency graph:
#   Phase 1 (parallel):
#     - stackit-gpu-vpc             (STACKIT routed virtual network)
#     - stackit-inference-platform  (STACKIT Object Storage S3 for LLM weights + Observability/Argus)
#   Phase 2:
#     - stackit-ske-gpu             (SKE cluster with Cilium CNI + Argus extension + L40S/H100/L4 GPU pools)
#   Phase 3 (parallel — reusing existing Helm/K8s modules from terraform/modules/):
#     - stackit-argocd              (reuses terraform/modules/argocd -> GitOps fleet sync from apps/infra/*)
#     - stackit-gpu-operator        (reuses terraform/modules/gke-gpu-operator -> NVIDIA GPU Operator + driver)
#     - stackit-gpu-dcgm            (reuses terraform/modules/gke-gpu-dcgm -> DCGM Exporter DaemonSet)
#     - stackit-gpu-scheduling      (reuses terraform/modules/gke-gpu-scheduling -> Volcano/Kueue gang scheduler)
#     - stackit-inference-gateway   (reuses terraform/modules/gke-inference-gateway -> Gateway API + InferencePool)
# ---------------------------------------------------------------------------------------------------------------------

unit "stackit-gpu-vpc" {
  source = "${get_repo_root()}/catalog/units/stackit-gpu-vpc"
  path   = "stackit-gpu-vpc"
}

unit "stackit-inference-platform" {
  source = "${get_repo_root()}/catalog/units/stackit-inference-platform"
  path   = "stackit-inference-platform"
}

unit "stackit-ske-gpu" {
  source = "${get_repo_root()}/catalog/units/stackit-ske-gpu"
  path   = "stackit-ske-gpu"
}

unit "stackit-argocd" {
  source = "${get_repo_root()}/catalog/units/stackit-argocd"
  path   = "stackit-argocd"
}

unit "stackit-gpu-operator" {
  source = "${get_repo_root()}/catalog/units/stackit-gpu-operator"
  path   = "stackit-gpu-operator"
}

unit "stackit-gpu-dcgm" {
  source = "${get_repo_root()}/catalog/units/stackit-gpu-dcgm"
  path   = "stackit-gpu-dcgm"
}

unit "stackit-gpu-scheduling" {
  source = "${get_repo_root()}/catalog/units/stackit-gpu-scheduling"
  path   = "stackit-gpu-scheduling"
}

unit "stackit-inference-gateway" {
  source = "${get_repo_root()}/catalog/units/stackit-inference-gateway"
  path   = "stackit-inference-gateway"
}
