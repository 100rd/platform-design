# ---------------------------------------------------------------------------------------------------------------------
# GKE GPU DCGM Exporter Module (WS-A — ml-infra)
# ---------------------------------------------------------------------------------------------------------------------
# Deploys the NVIDIA DCGM exporter as a DaemonSet on GKE GPU nodes via helm_release,
# exposing GPU metrics (utilisation, memory, temperature, power, XID/ECC errors) on
# :9400 for Prometheus / VictoriaMetrics scrape.
#
# The dcgm-exporter chart renders an optional Prometheus-Operator ServiceMonitor
# directly (serviceMonitor.enabled) so the metrics backend selects the target with a
# `release` label — this keeps the module free of kubernetes_manifest, which would
# require a live cluster at plan time and break mocked validation.
#
# ADR-0028: namespace and exporter workloads carry the Kubernetes-plane platform
# labels (dotted keys, platform.system = ml-infra).
# ---------------------------------------------------------------------------------------------------------------------

locals {
  # ADR-0028 Kubernetes-plane baseline labels for the ml-infra system.
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
# Namespace — labeled per ADR-0028; also flagged for monitoring discovery.
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
# DCGM exporter Helm release (DaemonSet) + optional ServiceMonitor.
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
      # DaemonSet metrics port.
      service = {
        type = "ClusterIP"
        port = var.exporter_port
      }

      # Run only on GPU nodes; tolerate the GPU taint.
      nodeSelector = var.gpu_node_selector
      tolerations = [
        {
          key      = "nvidia.com/gpu"
          operator = "Exists"
          effect   = "NoSchedule"
        }
      ]

      # ADR-0028 labels on the exporter pods.
      podLabels = local.platform_labels

      # Prometheus / VictoriaMetrics scrape via ServiceMonitor.
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
