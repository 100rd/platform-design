# ---------------------------------------------------------------------------------------------------------------------
# Provider & version constraints
# ---------------------------------------------------------------------------------------------------------------------
# Terraform (NOT OpenTofu). Renders an ArgoCD Application via the kubernetes provider's
# kubernetes_manifest resource. No helm provider here — the Application object itself is a
# CRD manifest; Helm rendering happens in-cluster, managed by ArgoCD.
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  required_version = "~> 1.11"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.25"
    }
  }
}
