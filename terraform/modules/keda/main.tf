# ---------------------------------------------------------------------------------------------------------------------
# KEDA — Kubernetes Event-Driven Autoscaling
# ---------------------------------------------------------------------------------------------------------------------

resource "helm_release" "keda" {
  name             = "keda"
  namespace        = var.namespace
  create_namespace = true
  repository       = "https://kedacore.github.io/charts"
  chart            = "keda"
  version          = var.keda_version

  wait          = true
  wait_for_jobs = true
  timeout       = 600

  values = [
    yamlencode({
      operator = {
        replicaCount = var.operator_replicas
      }
      metricsServer = {
        replicaCount = var.metrics_server_replicas
      }
      logging = {
        operator = {
          level = var.log_level
        }
      }
      prometheus = {
        metricServer = {
          enabled = var.enable_prometheus_metrics
        }
        operator = {
          enabled = var.enable_prometheus_metrics
        }
      }
    })
  ]
}
