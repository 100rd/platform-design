# ---------------------------------------------------------------------------------------------------------------------
# Scaleway GPU Inference — Live Deployment (fr-par)
# ---------------------------------------------------------------------------------------------------------------------
# Deploys the Scaleway Kapsule GPU inference stack in Paris (fr-par / fr-par-2).
# Environment-specific values come from project.hcl; region-specific from region.hcl.
#
# Reuses existing Helm/ArgoCD/K8s modules from terraform/modules/ alongside minimal
# Scaleway-native foundation modules (VPC/Private Network, Kapsule Dedicated, Object Storage/Cockpit).
#
# Usage:
#   terragrunt stack generate
#   terragrunt stack run plan
#   terragrunt stack run apply
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

# ---------------------------------------------------------------------------------------------------------------------
# Reused Helm / ArgoCD / K8s Units (backed by existing terraform/modules/*)
# ---------------------------------------------------------------------------------------------------------------------

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
