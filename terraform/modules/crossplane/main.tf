resource "helm_release" "crossplane" {
  name             = "crossplane"
  repository       = "https://charts.crossplane.io/stable"
  chart            = "crossplane"
  version          = var.chart_version
  namespace        = "crossplane-system"
  create_namespace = true

  values = [
    yamlencode({
      args = ["--enable-usages"]
      resourcesCrossplane = {
        limits = {
          memory = var.crossplane_memory_limit
          cpu    = var.crossplane_cpu_limit
        }
      }
    })
  ]
}

resource "helm_release" "provider_aws" {
  depends_on = [helm_release.crossplane]

  name       = "provider-family-aws"
  repository = "https://charts.crossplane.io/stable"
  chart      = "provider-family-aws"
  version    = var.provider_aws_version
  namespace  = "crossplane-system"
}
