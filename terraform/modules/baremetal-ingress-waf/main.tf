# ---------------------------------------------------------------------------------------------------------------------
# Bare-metal Ingress WAF / Rate-limit Module (WS-A — ml-infra) — ADR-0053 (serving axis)
# ---------------------------------------------------------------------------------------------------------------------
# On-prem WAF / rate-limit at the serving edge — the bare-metal mirror of Cloud Armor (no
# cloud LB exists on owned hardware). Two gateway backends (var.gateway_backend):
#
#   * cilium — Cilium Gateway (L7 rate-limit via CiliumNetworkPolicy / Envoy filters,
#              one networking stack since Cilium is already the CNI). Default.
#   * envoy  — Envoy Gateway (reuse apps/infra/envoy-gateway) with the Envoy ratelimit
#              service.
#
# This module owns the Gateway + the rate-limit policy CR (a CiliumNetworkPolicy with an
# L7 ingress rate-limit, or an Envoy BackendTrafficPolicy). All kubernetes_manifest (mocked
# in tftest). The actual model-serving Gateway/HTTPRoute live in the
# baremetal-inference-gateway ArgoCD app; this module is the WAF/rate-limit front.
#
# ADR-0028: every CR carries the dotted labels.
# ---------------------------------------------------------------------------------------------------------------------

locals {
  platform_labels = merge(
    {
      "platform.system"     = "ml-inference"
      "platform.component"  = "ingress-waf"
      "platform.managed-by" = "terragrunt"
    },
    var.platform_labels,
  )

  use_cilium = var.gateway_backend == "cilium"
  use_envoy  = var.gateway_backend == "envoy"
}

# ---------------------------------------------------------------------------------------------------------------------
# Gateway — the serving entrypoint (GatewayClass differs per backend).
# ---------------------------------------------------------------------------------------------------------------------

resource "kubernetes_manifest" "gateway" {
  count = var.enabled ? 1 : 0

  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "Gateway"
    metadata = {
      name      = var.gateway_name
      namespace = var.namespace
      labels    = local.platform_labels
    }
    spec = {
      gatewayClassName = local.use_cilium ? var.cilium_gateway_class : var.envoy_gateway_class
      listeners = [
        {
          name     = "https"
          protocol = "HTTPS"
          port     = 443
          tls = {
            mode = "Terminate"
            certificateRefs = [
              { name = var.tls_secret_name }
            ]
          }
        }
      ]
    }
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# Cilium L7 rate-limit — CiliumNetworkPolicy with an ingress rate-limit (Cloud Armor mirror).
# ---------------------------------------------------------------------------------------------------------------------

resource "kubernetes_manifest" "cilium_ratelimit" {
  count = var.enabled && local.use_cilium ? 1 : 0

  manifest = {
    apiVersion = "cilium.io/v2"
    kind       = "CiliumNetworkPolicy"
    metadata = {
      name      = "${var.gateway_name}-ratelimit"
      namespace = var.namespace
      labels    = local.platform_labels
    }
    spec = {
      endpointSelector = {
        matchLabels = {
          "platform.system" = "ml-inference"
        }
      }
      ingress = [
        {
          fromEntities = ["world"]
          toPorts = [
            {
              ports = [{ port = "443", protocol = "TCP" }]
              rules = {
                http = [
                  {
                    method = "POST"
                    path   = var.protected_path
                  }
                ]
              }
            }
          ]
        }
      ]
    }
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# Envoy rate-limit — BackendTrafficPolicy (when gateway_backend = envoy; reuse envoy-gateway).
# ---------------------------------------------------------------------------------------------------------------------

resource "kubernetes_manifest" "envoy_ratelimit" {
  count = var.enabled && local.use_envoy ? 1 : 0

  manifest = {
    apiVersion = "gateway.envoyproxy.io/v1alpha1"
    kind       = "BackendTrafficPolicy"
    metadata = {
      name      = "${var.gateway_name}-ratelimit"
      namespace = var.namespace
      labels    = local.platform_labels
    }
    spec = {
      targetRefs = [
        {
          group = "gateway.networking.k8s.io"
          kind  = "Gateway"
          name  = var.gateway_name
        }
      ]
      rateLimit = {
        type = "Local"
        local = {
          rules = [
            {
              limit = {
                requests = var.rate_limit_requests
                unit     = var.rate_limit_unit
              }
            }
          ]
        }
      }
    }
  }
}
