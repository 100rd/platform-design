# ---------------------------------------------------------------------------------------------------------------------
# HPA Defaults — Platform Component Autoscalers
# ---------------------------------------------------------------------------------------------------------------------
# Deploys default HPAs for platform components like CoreDNS.
# Gated by var.enabled to allow per-environment control.
# ---------------------------------------------------------------------------------------------------------------------

resource "kubernetes_horizontal_pod_autoscaler_v2" "coredns" {
  count = var.enabled ? 1 : 0

  metadata {
    name      = "coredns"
    namespace = "kube-system"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "platform.sh/component"        = "hpa-defaults"
    }
  }

  spec {
    min_replicas = 2
    max_replicas = 10

    scale_target_ref {
      api_version = "apps/v1"
      kind        = "Deployment"
      name        = "coredns"
    }

    metric {
      type = "Resource"
      resource {
        name = "cpu"
        target {
          type                = "Utilization"
          average_utilization = 70
        }
      }
    }

    metric {
      type = "Resource"
      resource {
        name = "memory"
        target {
          type                = "Utilization"
          average_utilization = 80
        }
      }
    }

    behavior {
      scale_down {
        stabilization_window_seconds = 300
        select_policy                = "Min"
        policy {
          type           = "Percent"
          value          = 10
          period_seconds = 60
        }
      }
      scale_up {
        stabilization_window_seconds = 0
        select_policy                = "Max"
        policy {
          type           = "Percent"
          value          = 100
          period_seconds = 15
        }
        policy {
          type           = "Pods"
          value          = 4
          period_seconds = 15
        }
      }
    }
  }
}
