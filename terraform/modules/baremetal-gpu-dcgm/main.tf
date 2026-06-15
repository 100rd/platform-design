# ---------------------------------------------------------------------------------------------------------------------
# Bare-metal GPU DCGM Module (WS-A — ml-infra) — ADR-0049 / ADR-0050
# ---------------------------------------------------------------------------------------------------------------------
# Deploys the NVIDIA DCGM exporter (DaemonSet) on the Talos GPU nodes exposing GPU metrics
# (utilisation, memory, temp, power, XID/ECC/NVLink) for VictoriaMetrics/Prometheus scrape,
# plus a GPU-health AUTO-TAINT CronJob that taints a node out of scheduling on a simulated
# XID burst (ports the EKS gpu-inference-dcgm behaviour). Honours the
# gpu-driver-updates.md post-update checklist.
#
# The dcgm-exporter chart renders its own ServiceMonitor (serviceMonitor.enabled) so the
# module stays free of kubernetes_manifest for the metrics path. The auto-taint CronJob is
# a kubernetes_manifest (mocked in tftest).
#
# ADR-0028: namespace + exporter + CronJob carry the Kubernetes-plane dotted labels.
# ---------------------------------------------------------------------------------------------------------------------

locals {
  platform_labels = merge(
    {
      "platform.system"     = "ml-infra"
      "platform.component"  = "observability"
      "platform.managed-by" = "terragrunt"
    },
    var.platform_labels,
  )
}

# ---------------------------------------------------------------------------------------------------------------------
# Namespace — labeled per ADR-0028; flagged for monitoring discovery.
# ---------------------------------------------------------------------------------------------------------------------

resource "kubernetes_namespace" "dcgm" {
  count = var.enabled ? 1 : 0

  metadata {
    name = var.namespace
    labels = merge(local.platform_labels, {
      "monitoring" = "true"
    })
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# DCGM exporter Helm release (DaemonSet) + ServiceMonitor.
# ---------------------------------------------------------------------------------------------------------------------

resource "helm_release" "dcgm_exporter" {
  count = var.enabled ? 1 : 0

  name       = "dcgm-exporter"
  repository = var.chart_repository
  chart      = "dcgm-exporter"
  version    = var.chart_version
  namespace  = kubernetes_namespace.dcgm[0].metadata[0].name
  timeout    = var.helm_timeout

  values = [
    yamlencode({
      service = {
        type = "ClusterIP"
        port = var.exporter_port
      }
      nodeSelector = var.gpu_node_selector
      tolerations = [
        {
          key      = "nvidia.com/gpu"
          operator = "Exists"
          effect   = "NoSchedule"
        }
      ]
      podLabels = local.platform_labels
      serviceMonitor = {
        enabled  = var.create_service_monitor
        interval = var.scrape_interval
        additionalLabels = merge(local.platform_labels, {
          "release" = var.service_monitor_release_label
        })
      }
    })
  ]
}

# ---------------------------------------------------------------------------------------------------------------------
# GPU-health auto-taint CronJob — taints a node NoSchedule on an XID-error burst
# (ports gpu-inference-dcgm; honours gpu-driver-updates.md). Gated by enable_auto_taint.
# ---------------------------------------------------------------------------------------------------------------------

resource "kubernetes_manifest" "gpu_health_autotaint" {
  count = var.enabled && var.enable_auto_taint ? 1 : 0

  manifest = {
    apiVersion = "batch/v1"
    kind       = "CronJob"
    metadata = {
      name      = "gpu-health-autotaint"
      namespace = var.namespace
      labels    = local.platform_labels
    }
    spec = {
      schedule = var.auto_taint_schedule
      jobTemplate = {
        spec = {
          template = {
            metadata = {
              labels = local.platform_labels
            }
            spec = {
              serviceAccountName = var.auto_taint_service_account
              restartPolicy      = "OnFailure"
              containers = [
                {
                  name  = "gpu-health-check"
                  image = var.auto_taint_image
                  env = [
                    { name = "DCGM_ENDPOINT", value = "http://dcgm-exporter.${var.namespace}.svc:${var.exporter_port}/metrics" },
                    { name = "XID_THRESHOLD", value = tostring(var.xid_error_threshold) },
                    { name = "TAINT_KEY", value = "nvidia.com/gpu-unhealthy" },
                  ]
                }
              ]
            }
          }
        }
      }
    }
  }
}
