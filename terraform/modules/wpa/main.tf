# ---------------------------------------------------------------------------------------------------------------------
# WPA — Watermark Pod Autoscaler (Datadog)
# ---------------------------------------------------------------------------------------------------------------------
# Deploys the Datadog Watermark Pod Autoscaler controller via Helm.
# Gated by var.enabled (disabled by default).
# ---------------------------------------------------------------------------------------------------------------------

resource "helm_release" "wpa" {
  count = var.enabled ? 1 : 0

  name             = "watermarkpodautoscaler"
  namespace        = var.namespace
  create_namespace = true
  repository       = "https://helm.datadoghq.com"
  chart            = "watermarkpodautoscaler"
  version          = var.wpa_version

  wait    = true
  timeout = 300

  values = [
    yamlencode({
      replicaCount = var.controller_replicas
    })
  ]
}
