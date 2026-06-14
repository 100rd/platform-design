# Gateway API / inference CRDs via kubernetes_manifest; provider mocked so plan/validate
# needs no live cluster.
mock_provider "kubernetes" {}

variables {
  inference_models = [
    { name = "domain-adapter", model_name = "domain-adapter", target_model = "domain-adapter-v3", criticality = "Critical" },
    { name = "summarizer", model_name = "summarizer", target_model = "summarizer-lora", criticality = "Standard" },
  ]
  platform_labels = {
    "platform.env"   = "staging"
    "platform.owner" = "team-ml-inference"
  }
}

run "creates_gateway_pool_route" {
  command = plan

  assert {
    condition     = length(kubernetes_manifest.gateway) == 1
    error_message = "A Gateway must be created when enabled."
  }

  assert {
    condition     = length(kubernetes_manifest.inference_pool) == 1
    error_message = "An InferencePool must be created when enabled."
  }

  assert {
    condition     = length(kubernetes_manifest.http_route) == 1
    error_message = "An HTTPRoute must be created when enabled."
  }
}

run "one_inference_model_per_entry" {
  command = plan

  assert {
    condition     = length(kubernetes_manifest.inference_model) == 2
    error_message = "Each inference_models entry must produce one InferenceModel."
  }

  assert {
    condition     = kubernetes_manifest.inference_model["domain-adapter"].manifest.spec.criticality == "Critical"
    error_message = "domain-adapter must be routed as Critical."
  }
}

run "body_based_router_annotation_on_by_default" {
  command = plan

  assert {
    condition     = kubernetes_manifest.gateway[0].manifest.metadata.annotations["networking.gke.io/enable-body-based-routing"] == "true"
    error_message = "Body-Based Router annotation must default to enabled."
  }
}

run "no_cloud_armor_without_policy" {
  command = plan

  assert {
    condition     = length(kubernetes_manifest.backend_policy) == 0
    error_message = "GCPBackendPolicy must not be created without a cloud_armor_policy_id."
  }
}

run "cloud_armor_attached_when_policy_provided" {
  command = plan

  variables {
    cloud_armor_policy_id = "projects/test/global/securityPolicies/gpu-inference-armor"
  }

  assert {
    condition     = length(kubernetes_manifest.backend_policy) == 1
    error_message = "GCPBackendPolicy must be created when a Cloud Armor policy is provided."
  }
}

run "disabled_creates_nothing" {
  command = plan

  variables {
    enabled = false
  }

  assert {
    condition     = (length(kubernetes_manifest.gateway) + length(kubernetes_manifest.inference_pool) + length(kubernetes_manifest.http_route) + length(kubernetes_manifest.inference_model)) == 0
    error_message = "Nothing should be created when enabled = false."
  }
}
