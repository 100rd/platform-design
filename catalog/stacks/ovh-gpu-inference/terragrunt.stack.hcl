# ---------------------------------------------------------------------------------------------------------------------
# OVHcloud GPU Inference Stack Template
# ---------------------------------------------------------------------------------------------------------------------
# Composable Terragrunt stack for deploying a sovereign EU OVHcloud MKS GPU inference platform.
#
# Dependency graph:
#   Phase 1 (parallel):
#     - ovh-gpu-vpc             (OVHcloud vRack Private Network + subnet + Public Cloud Gateway SNAT)
#     - ovh-inference-platform  (OVHcloud Object Storage S3 for LLM weights + Harbor Private Registry)
#   Phase 2:
#     - ovh-mks-gpu             (MKS Standard cluster with Cilium CNI + l40s-90 / h100-380 / l4-90 GPU pools)
#   Phase 3 (parallel — reusing existing Helm/K8s modules from terraform/modules/):
#     - ovh-argocd              (reuses terraform/modules/argocd -> GitOps fleet sync from apps/infra/*)
#     - ovh-gpu-operator        (reuses terraform/modules/gke-gpu-operator -> NVIDIA GPU Operator + driver)
#     - ovh-gpu-dcgm            (reuses terraform/modules/gke-gpu-dcgm -> DCGM Exporter DaemonSet)
#     - ovh-gpu-scheduling      (reuses terraform/modules/gke-gpu-scheduling -> Volcano/Kueue gang scheduler)
#     - ovh-inference-gateway   (reuses terraform/modules/gke-inference-gateway -> Gateway API + InferencePool)
# ---------------------------------------------------------------------------------------------------------------------

unit "ovh-gpu-vpc" {
  source = "${get_repo_root()}/catalog/units/ovh-gpu-vpc"
  path   = "ovh-gpu-vpc"
}

unit "ovh-inference-platform" {
  source = "${get_repo_root()}/catalog/units/ovh-inference-platform"
  path   = "ovh-inference-platform"
}

unit "ovh-mks-gpu" {
  source = "${get_repo_root()}/catalog/units/ovh-mks-gpu"
  path   = "ovh-mks-gpu"
}

unit "ovh-argocd" {
  source = "${get_repo_root()}/catalog/units/ovh-argocd"
  path   = "ovh-argocd"
}

unit "ovh-gpu-operator" {
  source = "${get_repo_root()}/catalog/units/ovh-gpu-operator"
  path   = "ovh-gpu-operator"
}

unit "ovh-gpu-dcgm" {
  source = "${get_repo_root()}/catalog/units/ovh-gpu-dcgm"
  path   = "ovh-gpu-dcgm"
}

unit "ovh-gpu-scheduling" {
  source = "${get_repo_root()}/catalog/units/ovh-gpu-scheduling"
  path   = "ovh-gpu-scheduling"
}

unit "ovh-inference-gateway" {
  source = "${get_repo_root()}/catalog/units/ovh-inference-gateway"
  path   = "ovh-inference-gateway"
}
