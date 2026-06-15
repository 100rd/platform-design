# ---------------------------------------------------------------------------------------------------------------------
# aws-eks-inference-gateway — model-/cache-aware serving front (ADR-0047 D1/D2/D3/D4)
# ---------------------------------------------------------------------------------------------------------------------
# The AWS mirror of the GKE inference gateway (gke-inference-gateway), using the v1 GA
# Gateway API Inference Extension CRDs:
#   * Gateway            — Envoy Gateway (default, ADR-0047 D2) or ALB (fallback, D3).
#   * InferencePool      — the set of vLLM replicas (selector + target port + EPP ref).
#   * InferenceObjective — per-workload routing/criticality (v1 GA; was InferenceModel).
#   * HTTPRoute          — binds the Gateway to the InferencePool.
#   * EPP (Deployment+Service) — the Endpoint Picker ext-proc, deployed EXPLICITLY
#     (the gateway does NOT install it — ADR-0047 D2, named deliverable).
#
# TLS terminates at the WAF/ALB in front of Envoy (var.tls_mode = terminate-at-lb,
# ADR-0047 D4); the Gateway listener stays HTTP on the trusted in-cluster hop.
#
# AWS WAF (ADR-0047 D4) is the reused `waf` module's WebACL; its ARN is wired here and
# associated with the serving LB by the catalog unit. Default-OFF (var.enabled) keeps
# the vLLM ClusterIP path until the gateway is canary-proven (ADR-0047 D5, revertible).
#
# kubernetes_manifest validates with the kubernetes provider mocked (gke-inference-gateway pattern).
# ADR-0028 labels (dotted keys, platform.system = ml-platform).
# ---------------------------------------------------------------------------------------------------------------------

locals {
  inference_objectives = { for o in var.inference_objectives : o.name => o }

  platform_labels = merge(
    {
      "platform.system"     = "ml-platform"
      "platform.component"  = "inference-gateway"
      "platform.managed-by" = "terragrunt"
    },
    var.platform_labels,
  )

  # AWS WAF binds to the upstream LB fronting Envoy (D4); surfaced as a Gateway
  # annotation so the LBC/association layer can pick it up. The same LB terminates
  # TLS (var.tls_mode = terminate-at-lb), so the Gateway listener below stays HTTP.
  gateway_annotations = var.waf_web_acl_arn != "" ? {
    "platform.aws/waf-web-acl-arn" = var.waf_web_acl_arn
    "platform.aws/tls-mode"        = var.tls_mode
  } : {}

  deploy_epp = var.enabled && var.deploy_epp
}

# ---------------------------------------------------------------------------------------------------------------------
# Gateway — Envoy Gateway (default) or ALB (fallback).
# ---------------------------------------------------------------------------------------------------------------------

resource "kubernetes_manifest" "gateway" {
  count = var.enabled ? 1 : 0

  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "Gateway"
    metadata = {
      name        = var.gateway_name
      namespace   = var.namespace
      labels      = local.platform_labels
      annotations = local.gateway_annotations
    }
    spec = {
      gatewayClassName = var.gateway_class
      listeners = [
        {
          name     = "http"
          protocol = "HTTP"
          port     = 80
        }
      ]
    }
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# InferencePool — the vLLM replica set + EPP extension reference (v1 GA).
# ---------------------------------------------------------------------------------------------------------------------

resource "kubernetes_manifest" "inference_pool" {
  count = var.enabled ? 1 : 0

  manifest = {
    apiVersion = "inference.networking.k8s.io/v1"
    kind       = "InferencePool"
    metadata = {
      name      = var.inference_pool_name
      namespace = var.namespace
      labels    = local.platform_labels
    }
    spec = {
      selector         = var.inference_pool_selector
      targetPortNumber = var.inference_pool_target_port
      extensionRef = {
        name = "${var.inference_pool_name}-epp"
      }
    }
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# InferenceObjective — per-workload routing/criticality (v1 GA; was InferenceModel).
# Multi-LoRA → one object per adapter (ADR-0047 D1).
# ---------------------------------------------------------------------------------------------------------------------

resource "kubernetes_manifest" "inference_objective" {
  for_each = var.enabled ? local.inference_objectives : {}

  manifest = {
    apiVersion = "inference.networking.k8s.io/v1"
    kind       = "InferenceObjective"
    metadata = {
      name      = each.value.name
      namespace = var.namespace
      labels    = local.platform_labels
    }
    spec = {
      criticality = each.value.criticality
      poolRef = {
        name = var.inference_pool_name
      }
      targetModels = [
        {
          name = each.value.target_model
        }
      ]
    }
  }

  depends_on = [kubernetes_manifest.inference_pool]
}

# ---------------------------------------------------------------------------------------------------------------------
# HTTPRoute — binds the Gateway to the InferencePool.
# ---------------------------------------------------------------------------------------------------------------------

resource "kubernetes_manifest" "http_route" {
  count = var.enabled ? 1 : 0

  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "HTTPRoute"
    metadata = {
      name      = "${var.inference_pool_name}-route"
      namespace = var.namespace
      labels    = local.platform_labels
    }
    spec = {
      parentRefs = [
        {
          name = var.gateway_name
        }
      ]
      hostnames = var.hostnames
      rules = [
        {
          backendRefs = [
            {
              group = "inference.networking.k8s.io"
              kind  = "InferencePool"
              name  = var.inference_pool_name
            }
          ]
        }
      ]
    }
  }

  depends_on = [kubernetes_manifest.inference_pool, kubernetes_manifest.gateway]
}

# ---------------------------------------------------------------------------------------------------------------------
# Endpoint Picker (EPP) — ext-proc Deployment + Service. Deployed EXPLICITLY (ADR-0047 D2);
# the gateway does NOT stand this up on its own. Routes on KV-cache + queue depth.
# ---------------------------------------------------------------------------------------------------------------------

resource "kubernetes_config_map" "epp" {
  count = local.deploy_epp ? 1 : 0

  metadata {
    name      = "${var.inference_pool_name}-epp-config"
    namespace = var.namespace
    labels    = local.platform_labels
  }

  data = var.epp_config
}

resource "kubernetes_deployment" "epp" {
  count = local.deploy_epp ? 1 : 0

  metadata {
    name      = "${var.inference_pool_name}-epp"
    namespace = var.namespace
    labels    = local.platform_labels
  }

  spec {
    replicas = var.epp_replicas

    selector {
      match_labels = {
        "app" = "${var.inference_pool_name}-epp"
      }
    }

    template {
      metadata {
        labels = merge(local.platform_labels, {
          "app" = "${var.inference_pool_name}-epp"
        })
      }
      spec {
        # Pod-level hardening (MED): run as the unprivileged nobody user, never root.
        security_context {
          run_as_non_root = true
          run_as_user     = 65534
        }

        container {
          name  = "epp"
          image = var.epp_image

          args = [
            "--pool-name", var.inference_pool_name,
            "--pool-namespace", var.namespace,
          ]

          port {
            name           = "grpc-ext-proc"
            container_port = 9002
          }

          env {
            name  = "INFERENCE_CRD_VERSION"
            value = var.inference_crd_version
          }

          # Bound the ext-proc (HIGH): requests so the scheduler can place it, a hard
          # memory cap so it cannot OOM-pressure the node. CPU is request-only to
          # avoid throttling latency-sensitive routing.
          resources {
            requests = {
              cpu    = var.epp_cpu_request
              memory = var.epp_memory_request
            }
            limits = {
              memory = var.epp_memory_limit
            }
          }

          # Container-level hardening (MED): no privilege escalation, read-only rootfs,
          # drop every Linux capability.
          security_context {
            allow_privilege_escalation = false
            read_only_root_filesystem  = true

            capabilities {
              drop = ["ALL"]
            }
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "epp" {
  count = local.deploy_epp ? 1 : 0

  metadata {
    name      = "${var.inference_pool_name}-epp"
    namespace = var.namespace
    labels    = local.platform_labels
  }

  spec {
    selector = {
      "app" = "${var.inference_pool_name}-epp"
    }

    port {
      name        = "grpc-ext-proc"
      port        = 9002
      target_port = 9002
    }
  }
}
