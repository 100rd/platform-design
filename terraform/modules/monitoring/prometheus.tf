resource "helm_release" "kube_prometheus_stack" {
  count = var.enable_prometheus ? 1 : 0

  name             = "kube-prometheus-stack"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  version          = "81.2.2" # Updated 2026-01-28 from 56.0.0
  namespace        = "monitoring"
  create_namespace = true

  # CRDs are managed by the platform-crds module (prometheus-operator-crds Helm chart)
  skip_crds = true

  values = [
    yamlencode({
      # Disable CRD installation — managed by platform-crds Terraform module
      crds = {
        enabled = false
      }
      prometheus = {
        prometheusSpec = {
          retention = "15d"
          storageSpec = {
            volumeClaimTemplate = {
              spec = {
                storageClassName = "gp3"
                accessModes      = ["ReadWriteOnce"]
                resources = {
                  requests = {
                    storage = "50Gi"
                  }
                }
              }
            }
          }
        }
      }
      grafana = {
        enabled = var.enable_grafana
        persistence = {
          enabled = true
          size    = "10Gi"
        }
        # Admin password managed via ExternalSecret - see apps/infra/observability/prometheus-stack/templates/external-secrets.yaml
        admin = {
          existingSecret = "grafana-admin-credentials"
          userKey        = "admin-user"
          passwordKey    = "admin-password"
        }
      }
      alertmanager = {
        enabled = true
        alertmanagerSpec = {
          storage = {
            volumeClaimTemplate = {
              spec = {
                storageClassName = "gp3"
                accessModes      = ["ReadWriteOnce"]
                resources = {
                  requests = {
                    storage = "10Gi"
                  }
                }
              }
            }
          }
        }
      }
    })
  ]
}
