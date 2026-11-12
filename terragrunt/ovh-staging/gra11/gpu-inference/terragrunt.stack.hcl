# ---------------------------------------------------------------------------------------------------------------------
# OVHcloud GPU Inference — Live Deployment (GRA11)
# ---------------------------------------------------------------------------------------------------------------------
# Deploys the OVHcloud MKS GPU inference stack in Gravelines (GRA11 / GRA).
# Reuses existing Helm/ArgoCD/K8s modules from terraform/modules/ alongside minimal
# OVHcloud-native foundation modules (vRack + Gateway, MKS Standard, Object Storage + Harbor).
#
# Usage:
#   terragrunt stack generate
#   terragrunt stack run plan
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

# ---------------------------------------------------------------------------------------------------------------------
# Reused Helm / ArgoCD / K8s Units (backed by existing terraform/modules/*)
# ---------------------------------------------------------------------------------------------------------------------

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
