# ---------------------------------------------------------------------------------------------------------------------
# ArgoCD Module
# ---------------------------------------------------------------------------------------------------------------------
# Installs ArgoCD via Helm with skip_crds = true (CRDs managed by platform-crds module).
# Supports HA and non-HA modes, server-side apply, and configurable resources.
# ---------------------------------------------------------------------------------------------------------------------

locals {
  # HA defaults: 2 replicas for controller/server/repo-server; non-HA: 1
  effective_server_replicas     = coalesce(var.server_replicas, var.ha_enabled ? 2 : 1)
  effective_controller_replicas = coalesce(var.controller_replicas, var.ha_enabled ? 2 : 1)
  effective_repo_server_replicas = coalesce(var.repo_server_replicas, var.ha_enabled ? 2 : 1)
}

resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.chart_version
  namespace        = var.namespace
  create_namespace = var.create_namespace

  # CRDs are managed by the platform-crds module
  skip_crds = true

  wait          = true
  wait_for_jobs = true
  timeout       = 600

  values = [
    yamlencode(merge(
      {
        # Global settings
        global = {
          revisionHistoryLimit = 3
        }

        # Application controller
        controller = {
          replicas = local.effective_controller_replicas
          resources = var.controller_resources

          metrics = {
            enabled = true
            serviceMonitor = {
              enabled = true
            }
          }
        }

        # API server
        server = {
          replicas = local.effective_server_replicas
          service = {
            type = var.server_service_type
          }

          metrics = {
            enabled = true
            serviceMonitor = {
              enabled = true
            }
          }
        }

        # Repo server
        repoServer = {
          replicas  = local.effective_repo_server_replicas
          resources = var.repo_server_resources

          metrics = {
            enabled = true
            serviceMonitor = {
              enabled = true
            }
          }
        }

        # Dex
        dex = {
          enabled = var.enable_dex
        }

        # Redis HA when HA mode is enabled
        redis-ha = {
          enabled = var.ha_enabled
        }

        redis = {
          enabled = !var.ha_enabled
        }

        # ApplicationSet controller
        applicationSet = {
          replicas = var.ha_enabled ? 2 : 1
        }

        # Configs
        configs = {
          cm = {
            "server.enable.server-side.apply" = "true"
          }
        }
      },
      var.additional_helm_values,
    ))
  ]
}
