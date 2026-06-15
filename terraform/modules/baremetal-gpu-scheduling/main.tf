# ---------------------------------------------------------------------------------------------------------------------
# Bare-metal GPU Scheduling Module (WS-A — ml-infra) — ADR-0049
# ---------------------------------------------------------------------------------------------------------------------
# Deploys Volcano as the secondary gang-scheduler for distributed GPU training, the EXACT
# queue taxonomy already specified in docs/transaction-analytics/06-uk-datacenters.md
# (H100 training pool + H200 serving pool, with the doc's weights and caps), and the DRA
# DeviceClass / ResourceClaimTemplate objects for H100 / H200 / L40S + fractional GPU
# (folds the gpu-inference-dra shape).
#
# Volcano controller install is a helm_release; the Queue / DeviceClass /
# ResourceClaimTemplate CRs are kubernetes_manifest (require the CRDs on a live cluster, so
# mocked in tftest — same pattern as gke-gpu-scheduling / gke-gpu-dranet).
#
# ADR-0028: namespace + scheduler workloads + every CR carry the dotted labels.
# ---------------------------------------------------------------------------------------------------------------------

locals {
  platform_labels = merge(
    {
      "platform.system"     = "ml-infra"
      "platform.component"  = "scheduler"
      "platform.managed-by" = "terragrunt"
    },
    var.platform_labels,
  )

  deploy_volcano = var.enabled && var.scheduler == "volcano"

  # UK queue taxonomy (06-uk-datacenters.md) — keyed by name for stable for_each addresses.
  queues = var.enabled ? { for q in var.volcano_queues : q.name => q } : {}

  # DRA device classes for H100/H200/L40S + fractional — keyed by name.
  device_classes = var.enabled && var.dra_enabled ? { for d in var.dra_device_classes : d.name => d } : {}
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
# Volcano — gang-scheduling secondary scheduler (the UK doc's named choice).
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
        scheduler_podLabels  = local.platform_labels
        controller_podLabels = local.platform_labels
        scheduler_tolerations = [
          {
            key      = "nvidia.com/gpu"
            operator = "Exists"
            effect   = "NoSchedule"
          }
        ]
      }
    })
  ]
}

# ---------------------------------------------------------------------------------------------------------------------
# Volcano Queues — the EXACT UK taxonomy (06-uk-datacenters.md): H100 training pool
# (training-default/-bootstrap/-urgent) + H200 serving pool (serving-vllm/eval-judge/
# engine-build/batch-rescore), with the doc's weights and the training-urgent cap of 2.
# ---------------------------------------------------------------------------------------------------------------------

resource "kubernetes_manifest" "volcano_queue" {
  for_each = local.queues

  manifest = {
    apiVersion = "scheduling.volcano.sh/v1beta1"
    kind       = "Queue"
    metadata = {
      name = each.value.name
      labels = merge(local.platform_labels, {
        "gpu.platform/pool" = each.value.pool
      })
    }
    spec = merge(
      {
        weight      = each.value.weight
        reclaimable = each.value.reclaimable
      },
      each.value.capability_jobs == null ? {} : {
        capability = {
          "volcano.sh/job-count" = tostring(each.value.capability_jobs)
        }
      },
    )
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# DRA DeviceClass — H100/H200/L40S + fractional GPU (folds gpu-inference-dra).
# ---------------------------------------------------------------------------------------------------------------------

resource "kubernetes_manifest" "dra_device_class" {
  for_each = local.device_classes

  manifest = {
    apiVersion = "resource.k8s.io/v1"
    kind       = "DeviceClass"
    metadata = {
      name   = each.value.name
      labels = local.platform_labels
    }
    spec = {
      selectors = [
        {
          cel = {
            expression = "device.driver == 'gpu.nvidia.com' && device.attributes['gpu.nvidia.com'].productName == '${each.value.product_name}'"
          }
        }
      ]
    }
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# DRA ResourceClaimTemplate — one per device class so Volcano schedules GPU as a claim.
# ---------------------------------------------------------------------------------------------------------------------

resource "kubernetes_manifest" "dra_claim_template" {
  for_each = local.device_classes

  manifest = {
    apiVersion = "resource.k8s.io/v1"
    kind       = "ResourceClaimTemplate"
    metadata = {
      name      = "${each.value.name}-claim"
      namespace = var.namespace
      labels    = local.platform_labels
    }
    spec = {
      spec = {
        devices = {
          requests = [
            {
              name            = "gpu"
              deviceClassName = each.value.name
              count           = each.value.count
            }
          ]
        }
      }
    }
  }
}
