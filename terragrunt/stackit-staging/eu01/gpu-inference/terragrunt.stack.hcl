# ---------------------------------------------------------------------------------------------------------------------
# STACKIT GPU Inference — Live Deployment (eu01)
# ---------------------------------------------------------------------------------------------------------------------
# Deploys the STACKIT SKE GPU inference stack in region eu01.
# Reuses existing Helm/ArgoCD/K8s modules from terraform/modules/ alongside minimal
# STACKIT-native foundation modules (Network, SKE, Object Storage, Observability/Argus).
#
# Usage:
#   terragrunt stack generate
#   terragrunt stack run plan
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

# ---------------------------------------------------------------------------------------------------------------------
# Reused Helm / ArgoCD / K8s Units (backed by existing terraform/modules/*)
# ---------------------------------------------------------------------------------------------------------------------

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
