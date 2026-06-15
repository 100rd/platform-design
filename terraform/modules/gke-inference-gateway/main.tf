# ---------------------------------------------------------------------------------------------------------------------
# GKE Inference Gateway — model-/KV-cache-aware serving front for vLLM (ADR-0042 D4)
# ---------------------------------------------------------------------------------------------------------------------
# Replaces the plain ClusterIP front (gpu-inference-vllm) with the Gateway API inference
# extension so requests route on KV-cache utilisation, queue depth, and per-replica load
# instead of round-robin.
#
# Objects (all kubernetes_manifest; providers mocked in tftest):
#   * Gateway          — the GKE inference GatewayClass entrypoint.
#   * InferencePool    — the set of vLLM replicas (selector + target port + EPP ref).
#   * InferenceObjective   — per-model routing + criticality (multi-LoRA → multiple models).
#   * HTTPRoute        — binds the Gateway to the InferencePool.
#   * GCPBackendPolicy — attaches the Cloud Armor policy (ADR-0042 D5) when provided.
#
# ADR-0028: objects carry the Kubernetes-plane platform labels (dotted keys).
# ---------------------------------------------------------------------------------------------------------------------

locals {
  inference_models = { for m in var.inference_models : m.name => m }

  platform_labels = merge(
    {
      "platform.system"     = "ml-inference"
      "platform.component"  = "inference-gateway"
      "platform.managed-by" = "terragrunt"
    },
    var.platform_labels,
  )

  # Body-Based Router reads the model name from the OpenAI-style request body into a
  # header for model-aware routing; surfaced as a Gateway annotation.
  gateway_annotations = var.enable_body_based_router ? {
    "networking.gke.io/enable-body-based-routing" = "true"
  } : {}
}

# ---------------------------------------------------------------------------------------------------------------------
# Gateway — GKE inference GatewayClass entrypoint.
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
# InferencePool — the set of vLLM replicas, with the endpoint picker (EPP).
# ---------------------------------------------------------------------------------------------------------------------

resource "kubernetes_manifest" "inference_pool" {
  count = var.enabled ? 1 : 0

  manifest = {
    apiVersion = "inference.networking.x-k8s.io/v1alpha2"
    kind       = "InferencePool"
    metadata = {
      name      = var.inference_pool_name
      namespace = var.namespace
      labels    = local.platform_labels
    }
    spec = {
      targetPortNumber = var.inference_pool_target_port
      selector         = var.inference_pool_selector
      extensionRef = {
        name = var.endpoint_picker_name
      }
    }
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# InferenceObjective — per-model routing + criticality (multi-LoRA → multiple models).
# ---------------------------------------------------------------------------------------------------------------------

resource "kubernetes_manifest" "inference_model" {
  for_each = var.enabled ? local.inference_models : {}

  manifest = {
    apiVersion = "inference.networking.x-k8s.io/v1alpha2"
    kind       = "InferenceObjective"
    metadata = {
      name      = each.value.name
      namespace = var.namespace
      labels    = local.platform_labels
    }
    spec = {
      modelName   = each.value.model_name
      criticality = each.value.criticality
      poolRef = {
        name = var.inference_pool_name
      }
      targetModels = [
        {
          name   = each.value.target_model
          weight = each.value.weight
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
      name      = "${var.gateway_name}-route"
      namespace = var.namespace
      labels    = local.platform_labels
    }
    spec = {
      parentRefs = [
        { name = var.gateway_name }
      ]
      hostnames = var.hostnames
      rules = [
        {
          backendRefs = [
            {
              group = "inference.networking.x-k8s.io"
              kind  = "InferencePool"
              name  = var.inference_pool_name
            }
          ]
        }
      ]
    }
  }

  depends_on = [kubernetes_manifest.gateway, kubernetes_manifest.inference_pool]
}

# ---------------------------------------------------------------------------------------------------------------------
# GCPBackendPolicy — attach the Cloud Armor security policy (ADR-0042 D5) when provided.
# ---------------------------------------------------------------------------------------------------------------------

resource "kubernetes_manifest" "backend_policy" {
  count = var.enabled && var.cloud_armor_policy_id != null ? 1 : 0

  manifest = {
    apiVersion = "networking.gke.io/v1"
    kind       = "GCPBackendPolicy"
    metadata = {
      name      = "${var.inference_pool_name}-armor"
      namespace = var.namespace
      labels    = local.platform_labels
    }
    spec = {
      targetRef = {
        group = "inference.networking.x-k8s.io"
        kind  = "InferencePool"
        name  = var.inference_pool_name
      }
      default = {
        securityPolicy = var.cloud_armor_policy_id
      }
    }
  }

  depends_on = [kubernetes_manifest.inference_pool]
}
