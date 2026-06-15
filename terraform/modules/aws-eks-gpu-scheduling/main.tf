# ---------------------------------------------------------------------------------------------------------------------
# aws-eks-gpu-scheduling — Volcano gang scheduler + queues + DRA device classes (ADR-0044 D2/D3)
# ---------------------------------------------------------------------------------------------------------------------
# Combines the GKE gke-gpu-scheduling (Volcano) and the DRA device-class half of
# ADR-0044 D2 into one AWS module:
#   * Volcano as a secondary scheduler (gang + dra + binpack + topology + proportion)
#     with training/inference/batch fair-share Queues.
#   * DRA DeviceClass objects (typed GPU requests by productName, ADR-0044 D2) and
#     ResourceClaimTemplates (single-GPU / island / MIG) as kubernetes_manifest.
#
# kubernetes_manifest validates with the kubernetes provider mocked (no live cluster
# at plan/validate); same approach as gke-inference-gateway.
#
# Default-OFF (var.enabled). ADR-0028 labels (dotted keys, platform.system=ml-platform).
# ---------------------------------------------------------------------------------------------------------------------

locals {
  platform_labels = merge(
    {
      "platform.system"     = "ml-platform"
      "platform.component"  = "gpu-scheduling"
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

  device_class_objs   = var.enabled ? var.device_classes : {}
  claim_template_objs = var.enabled ? var.resource_claim_templates : {}
}

resource "kubernetes_namespace" "scheduling" {
  count = var.enabled ? 1 : 0

  metadata {
    name   = var.namespace
    labels = local.platform_labels
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# Volcano scheduler (gang + dra + binpack + topology + proportion).
# ---------------------------------------------------------------------------------------------------------------------

resource "helm_release" "volcano" {
  count = var.enabled ? 1 : 0

  name       = "volcano"
  repository = var.chart_repository
  chart      = "volcano"
  version    = var.chart_version
  namespace  = kubernetes_namespace.scheduling[0].metadata[0].name
  timeout    = var.helm_timeout

  values = [
    yamlencode({
      custom = {
        scheduler_replicas  = var.scheduler_replicas
        controller_replicas = var.controller_replicas
        # GPU-weighted bin-packing + gang + dra + topology + proportion.
        scheduler_config_override = yamlencode({
          actions = "enqueue, allocate, backfill"
          tiers = [
            {
              plugins = concat(
                [
                  { name = "priority" },
                  { name = "gang" },
                  { name = "conformance" },
                ],
                var.enable_dra ? [{ name = "dra" }] : [],
              )
            },
            {
              plugins = [
                { name = "proportion" },
                { name = "nodeorder" },
                {
                  name = "binpack"
                  arguments = {
                    "binpack.weight"                   = 10
                    "binpack.resources"                = "nvidia.com/gpu"
                    "binpack.resources.nvidia.com/gpu" = 100
                  }
                },
              ]
            },
          ]
        })
      }
      basic = {
        scheduler_podLabels  = local.platform_labels
        controller_podLabels = local.platform_labels
        tolerations          = local.gpu_tolerations
      }
    })
  ]
}

# ---------------------------------------------------------------------------------------------------------------------
# DRA DeviceClass objects — typed GPU requests by productName (ADR-0044 D2). Cluster-scoped.
# ---------------------------------------------------------------------------------------------------------------------

resource "kubernetes_manifest" "device_class" {
  for_each = local.device_class_objs

  manifest = {
    apiVersion = "resource.k8s.io/v1"
    kind       = "DeviceClass"
    metadata = {
      name   = each.key
      labels = local.platform_labels
    }
    spec = {
      selectors = [
        {
          cel = {
            expression = each.value
          }
        }
      ]
    }
  }

  depends_on = [helm_release.volcano]
}

# ---------------------------------------------------------------------------------------------------------------------
# ResourceClaimTemplates — single-GPU / island / MIG (ADR-0044 D2). Namespaced.
# ---------------------------------------------------------------------------------------------------------------------

resource "kubernetes_manifest" "resource_claim_template" {
  for_each = local.claim_template_objs

  manifest = {
    apiVersion = "resource.k8s.io/v1"
    kind       = "ResourceClaimTemplate"
    metadata = {
      name      = each.key
      namespace = var.dra_namespace
      labels    = local.platform_labels
    }
    spec = {
      spec = {
        devices = {
          requests = [
            {
              name            = "gpu"
              deviceClassName = each.value
              allocationMode  = "ExactCount"
              count           = 1
            }
          ]
        }
      }
    }
  }

  depends_on = [kubernetes_manifest.device_class]
}
