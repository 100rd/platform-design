# ---------------------------------------------------------------------------------------------------------------------
# GPU Inference ArgoCD Configuration
# ---------------------------------------------------------------------------------------------------------------------
# Creates ArgoCD AppProject and ApplicationSets for gpu-inference fleet management.
# Deployed on the Hub (platform) cluster alongside the existing ArgoCD instance.
# ---------------------------------------------------------------------------------------------------------------------

resource "kubernetes_manifest" "gpu_inference_project" {
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "AppProject"
    metadata = {
      name      = "gpu-inference"
      namespace = var.argocd_namespace
    }
    spec = {
      description = "GPU Inference cluster fleet management"
      sourceRepos = [var.gpu_inference_repo_url]
      destinations = [
        {
          server    = "https://kubernetes.default.svc"
          namespace = "gpu-inference-*"
        }
      ]
      clusterResourceWhitelist = [
        { group = "*", kind = "Namespace" },
        { group = "*", kind = "ClusterRole" },
        { group = "*", kind = "ClusterRoleBinding" },
      ]
      namespaceResourceWhitelist = [
        { group = "*", kind = "*" }
      ]
    }
  }
}

resource "kubernetes_manifest" "gpu_inference_appset" {
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "ApplicationSet"
    metadata = {
      name      = "gpu-inference-apps"
      namespace = var.argocd_namespace
    }
    spec = {
      generators = [
        {
          git = {
            repoURL  = var.gpu_inference_repo_url
            revision = "HEAD"
            directories = [
              { path = "${var.gpu_inference_repo_path}/*" }
            ]
          }
        }
      ]
      template = {
        metadata = {
          name = "gpu-inference-{{path.basename}}"
        }
        spec = {
          project = "gpu-inference"
          source = {
            repoURL        = var.gpu_inference_repo_url
            targetRevision = "HEAD"
            path           = "{{path}}"
          }
          destination = {
            server    = "https://kubernetes.default.svc"
            namespace = "gpu-inference-{{path.basename}}"
          }
          syncPolicy = {
            automated = {
              prune    = true
              selfHeal = true
            }
            syncOptions = ["CreateNamespace=true"]
          }
        }
      }
    }
  }
}
