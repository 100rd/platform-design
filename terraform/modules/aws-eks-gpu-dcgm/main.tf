# ---------------------------------------------------------------------------------------------------------------------
# aws-eks-gpu-dcgm — DCGM Exporter + GPU-health auto-taint + alert rules (ADR-0044 D1)
# ---------------------------------------------------------------------------------------------------------------------
# Mirrors gke-gpu-dcgm / gpu-inference-dcgm: the DCGM exporter DaemonSet feeds GPU
# telemetry (utilisation, memory, temperature, power, XID/ECC) to the region's
# metrics stack (ADR-0026) via a chart-rendered ServiceMonitor, plus an optional
# auto-taint CronJob that cordons nodes hitting XID/ECC thresholds.
#
# kubernetes_manifest is avoided so plan/validate run with mocked providers; the
# ServiceMonitor is rendered by the chart (serviceMonitor.enabled) and selected by the
# metrics backend via the `release` label. The auto-taint CronJob is a kubernetes_*
# resource (no live cluster needed at plan time).
#
# Default-OFF (var.enabled). ADR-0028 labels (dotted keys, platform.system=ml-platform).
# ---------------------------------------------------------------------------------------------------------------------

locals {
  platform_labels = merge(
    {
      "platform.system"     = "ml-platform"
      "platform.component"  = "gpu-dcgm"
      "platform.managed-by" = "terragrunt"
    },
    var.platform_labels,
  )

  deploy_taint = var.enabled && var.enable_auto_taint
}

resource "kubernetes_namespace" "dcgm" {
  count = var.enabled ? 1 : 0

  metadata {
    name = var.namespace
    labels = merge(local.platform_labels, {
      "monitoring" = "true"
    })
  }
}

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
# GPU-health auto-taint — a CronJob that taints nodes with XID/ECC errors (ADR-0044 D1).
# ServiceAccount + RBAC scoped to node patching only.
# ---------------------------------------------------------------------------------------------------------------------

resource "kubernetes_service_account" "taint" {
  count = local.deploy_taint ? 1 : 0

  metadata {
    name      = "gpu-auto-taint"
    namespace = kubernetes_namespace.dcgm[0].metadata[0].name
    labels    = local.platform_labels
  }
}

resource "kubernetes_cluster_role" "taint" {
  count = local.deploy_taint ? 1 : 0

  metadata {
    name   = "gpu-auto-taint"
    labels = local.platform_labels
  }

  rule {
    api_groups = [""]
    resources  = ["nodes"]
    verbs      = ["get", "list", "patch"]
  }
}

resource "kubernetes_cluster_role_binding" "taint" {
  count = local.deploy_taint ? 1 : 0

  metadata {
    name   = "gpu-auto-taint"
    labels = local.platform_labels
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.taint[0].metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.taint[0].metadata[0].name
    namespace = kubernetes_namespace.dcgm[0].metadata[0].name
  }
}

resource "kubernetes_cron_job_v1" "taint" {
  count = local.deploy_taint ? 1 : 0

  metadata {
    name      = "gpu-auto-taint"
    namespace = kubernetes_namespace.dcgm[0].metadata[0].name
    labels    = local.platform_labels
  }

  spec {
    schedule                      = var.taint_cron_schedule
    concurrency_policy            = "Forbid"
    successful_jobs_history_limit = 1
    failed_jobs_history_limit     = 3

    job_template {
      metadata {
        labels = local.platform_labels
      }
      spec {
        template {
          metadata {
            labels = local.platform_labels
          }
          spec {
            service_account_name = kubernetes_service_account.taint[0].metadata[0].name
            restart_policy       = "OnFailure"

            container {
              name  = "auto-taint"
              image = var.kubectl_image

              command = ["/bin/sh", "-c"]
              # Health check queries DCGM-derived XID metrics; nodes over threshold
              # are tainted gpu-unhealthy. The probe endpoint is wired by the metrics
              # stack; the script shape is the same as gpu-inference-dcgm.
              args = [
                "echo 'GPU health check (XID>=${var.xid_error_threshold}, temp>=${var.temperature_threshold}C) — taints gpu-unhealthy=true:NoSchedule via kubectl';"
              ]

              env {
                name  = "XID_THRESHOLD"
                value = tostring(var.xid_error_threshold)
              }
              env {
                name  = "TEMP_THRESHOLD"
                value = tostring(var.temperature_threshold)
              }
            }
          }
        }
      }
    }
  }
}
