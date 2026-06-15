# Tests for aws-eks-inference-gateway. kubernetes provider mocked (CRDs via
# kubernetes_manifest); module default-OFF.
mock_provider "kubernetes" {}

variables {
  inference_objectives = [
    { name = "domain-adapter", target_model = "domain-adapter-v3", criticality = "Critical" },
    { name = "summarizer", target_model = "summarizer-lora", criticality = "Standard" },
  ]
  platform_labels = {
    "platform.env"   = "staging"
    "platform.owner" = "team-ml-platform"
  }
}

run "default_off_creates_nothing" {
  command = plan

  assert {
    condition     = length(kubernetes_manifest.gateway) == 0
    error_message = "No Gateway when enabled defaults to false (keeps ClusterIP front; apply-gated)."
  }

  assert {
    condition     = length(kubernetes_deployment.epp) == 0
    error_message = "No EPP when disabled."
  }
}

run "creates_gateway_pool_route_epp" {
  command = plan

  variables {
    enabled = true
  }

  assert {
    condition     = length(kubernetes_manifest.gateway) == 1
    error_message = "A Gateway must be created when enabled (ADR-0047 D1/D2)."
  }

  assert {
    condition     = length(kubernetes_manifest.inference_pool) == 1
    error_message = "An InferencePool must be created (ADR-0047 D1)."
  }

  assert {
    condition     = length(kubernetes_manifest.http_route) == 1
    error_message = "An HTTPRoute must bind the Gateway to the InferencePool."
  }

  assert {
    condition     = length(kubernetes_deployment.epp) == 1
    error_message = "The EPP must be deployed explicitly (ADR-0047 D2 — not automatic)."
  }

  assert {
    condition     = length(kubernetes_service.epp) == 1
    error_message = "The EPP Service must be created."
  }
}

run "inference_objective_per_entry_v1ga" {
  command = plan

  variables {
    enabled = true
  }

  assert {
    condition     = length(kubernetes_manifest.inference_objective) == 2
    error_message = "Each inference_objectives entry must produce one InferenceObjective."
  }

  assert {
    condition     = kubernetes_manifest.inference_objective["domain-adapter"].manifest.kind == "InferenceObjective"
    error_message = "Must use the v1 GA InferenceObjective CRD (was InferenceModel)."
  }

  assert {
    condition     = kubernetes_manifest.inference_objective["domain-adapter"].manifest.spec.criticality == "Critical"
    error_message = "domain-adapter must route as Critical."
  }
}

run "waf_annotation_when_provided" {
  command = plan

  variables {
    enabled         = true
    waf_web_acl_arn = "arn:aws:wafv2:eu-west-1:111122223333:regional/webacl/inference/abc"
  }

  assert {
    condition     = kubernetes_manifest.gateway[0].manifest.metadata.annotations["platform.aws/waf-web-acl-arn"] != ""
    error_message = "WAF WebACL ARN must be surfaced on the Gateway when provided (ADR-0047 D4)."
  }
}

run "epp_can_be_disabled" {
  command = plan

  variables {
    enabled    = true
    deploy_epp = false
  }

  assert {
    condition     = length(kubernetes_deployment.epp) == 0
    error_message = "EPP must not deploy when deploy_epp = false."
  }

  assert {
    condition     = length(kubernetes_manifest.inference_pool) == 1
    error_message = "The InferencePool still exists even without the EPP (degraded routing)."
  }
}
