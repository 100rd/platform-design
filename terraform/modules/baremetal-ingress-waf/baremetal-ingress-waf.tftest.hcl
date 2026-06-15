# ---------------------------------------------------------------------------------------------------------------------
# Tests for the baremetal-ingress-waf module. The kubernetes provider is mocked; assertions
# run at plan time over the Gateway + rate-limit backends (ADR-0053 serving axis).
# ---------------------------------------------------------------------------------------------------------------------

mock_provider "kubernetes" {}

variables {
  enabled = true
  platform_labels = {
    "platform.env"   = "staging"
    "platform.owner" = "team-data"
  }
}

run "disabled_creates_nothing" {
  command = plan

  variables {
    enabled = false
  }

  assert {
    condition     = length(kubernetes_manifest.gateway) == 0
    error_message = "No Gateway when enabled = false."
  }
}

run "cilium_backend_by_default" {
  command = plan

  assert {
    condition     = length(kubernetes_manifest.gateway) == 1
    error_message = "Serving Gateway must be created when enabled = true."
  }

  # Default backend = cilium → Cilium rate-limit, no Envoy policy.
  assert {
    condition     = length(kubernetes_manifest.cilium_ratelimit) == 1
    error_message = "Cilium rate-limit policy must be created with the cilium backend (Cloud Armor mirror, ADR-0053)."
  }

  assert {
    condition     = length(kubernetes_manifest.envoy_ratelimit) == 0
    error_message = "Envoy policy must NOT be created with the cilium backend."
  }

  assert {
    condition     = kubernetes_manifest.gateway[0].manifest.spec.gatewayClassName == var.cilium_gateway_class
    error_message = "Gateway must use the Cilium GatewayClass by default."
  }
}

run "envoy_backend_when_selected" {
  command = plan

  variables {
    gateway_backend = "envoy"
  }

  assert {
    condition     = length(kubernetes_manifest.envoy_ratelimit) == 1
    error_message = "Envoy rate-limit policy must be created with the envoy backend."
  }

  assert {
    condition     = length(kubernetes_manifest.cilium_ratelimit) == 0
    error_message = "Cilium policy must NOT be created with the envoy backend."
  }
}

run "gateway_carries_adr0028_labels" {
  command = plan

  assert {
    condition     = kubernetes_manifest.gateway[0].manifest.metadata.labels["platform.system"] == "ml-inference"
    error_message = "Gateway must carry platform.system = ml-inference (ADR-0028)."
  }
}
