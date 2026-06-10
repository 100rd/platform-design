# ---------------------------------------------------------------------------------------------------------------------
# GKE GPU Batch Scheduling Module (WS-A — ml-infra)
# ---------------------------------------------------------------------------------------------------------------------
# Deploys a batch/queueing scheduler on a GKE cluster for GPU analysis workloads.
#
# Default is Volcano (native gang scheduling for distributed training, secondary
# scheduler — selected by ADR-0036 for WS-A and matching the EKS gpu-inference-volcano
# stack). Kueue (job-level queueing, quota and fair-sharing) is selectable via
# var.scheduler = "kueue". Exactly one is deployed, and the whole module is gated by
# var.enabled so a cluster can fall back to the default kube-scheduler.
#
# Queue/ClusterQueue/ResourceFlavor custom resources are intentionally NOT created
# here: those CRs require a live cluster (kubernetes_manifest) at plan time, which
# would break mocked validation. They are applied by the GitOps/ArgoCD layer once the
# CRDs exist. This module owns the controller install + namespace labeling only.
#
# ADR-0028: namespace and scheduler workloads carry the Kubernetes-plane platform
# labels (dotted keys, platform.system = ml-infra).
# ---------------------------------------------------------------------------------------------------------------------

locals {
  deploy_kueue   = var.enabled && var.scheduler == "kueue"
  deploy_volcano = var.enabled && var.scheduler == "volcano"

  # ADR-0028 Kubernetes-plane baseline labels for the ml-infra system.
  platform_labels = merge(
    {
      "platform.system"     = "ml-infra"
      "platform.component"  = "scheduler"
      "platform.managed-by" = "terragrunt"
    },
    var.platform_labels,
  )

  gpu_tolerations = var.manage_gpu_taints ? [
    {
      key      = "nvidia.com/gpu"
      operator = "Exists"
      effect   = "NoSchedule"
    }
  ] : []
}

# ---------------------------------------------------------------------------------------------------------------------
# Namespace — labeled per ADR-0028.
# ---------------------------------------------------------------------------------------------------------------------

resource "kubernetes_namespace" "scheduling" {
  count = var.enabled ? 1 : 0

  metadata {
    name   = var.namespace
    labels = local.platform_labels
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# Kueue — alternative GKE batch queueing scheduler.
# ---------------------------------------------------------------------------------------------------------------------

resource "helm_release" "kueue" {
  count = local.deploy_kueue ? 1 : 0

  name       = "kueue"
  repository = var.kueue_chart_repository
  chart      = "kueue"
  version    = var.kueue_chart_version
  namespace  = kubernetes_namespace.scheduling[0].metadata[0].name
  timeout    = var.helm_timeout

  values = [
    yamlencode({
      controllerManager = {
        manager = {
          podLabels   = local.platform_labels
          tolerations = local.gpu_tolerations
        }
      }
    })
  ]
}

# ---------------------------------------------------------------------------------------------------------------------
# Volcano — default gang-scheduling batch scheduler (ADR-0036 selection for WS-A).
# ---------------------------------------------------------------------------------------------------------------------

resource "helm_release" "volcano" {
  count = local.deploy_volcano ? 1 : 0

  name       = "volcano"
  repository = var.volcano_chart_repository
  chart      = "volcano"
  version    = var.volcano_chart_version
  namespace  = kubernetes_namespace.scheduling[0].metadata[0].name
  timeout    = var.helm_timeout

  values = [
    yamlencode({
      custom = {
        scheduler_podLabels   = local.platform_labels
        controller_podLabels  = local.platform_labels
        scheduler_tolerations = local.gpu_tolerations
      }
    })
  ]
}
