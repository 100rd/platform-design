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
  # When enabled the WAF WebACL ARN is required (ADR-0047 D4 validation). Provided here so
  # the enabled runs below satisfy the variable validation; the default-OFF run omits it.
  waf_web_acl_arn = "arn:aws:wafv2:eu-west-1:111122223333:regional/webacl/inference/abc"
}

run "default_off_creates_nothing" {
  command = plan

  variables {
    # default-OFF must hold even with no WAF ARN (validation only bites when enabled).
    waf_web_acl_arn = ""
  }

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

run "epp_is_bound_and_hardened" {
  command = plan

  variables {
    enabled = true
  }

  # HIGH: the EPP Deployment must be bound — requests + a memory limit, no unbounded ext-proc.
  assert {
    condition     = kubernetes_deployment.epp[0].spec[0].template[0].spec[0].container[0].resources[0].requests.cpu == "100m"
    error_message = "EPP must declare a CPU request (default 100m) — no unbounded Deployment."
  }

  assert {
    condition     = kubernetes_deployment.epp[0].spec[0].template[0].spec[0].container[0].resources[0].requests.memory == "128Mi"
    error_message = "EPP must declare a memory request (default 128Mi)."
  }

  assert {
    condition     = kubernetes_deployment.epp[0].spec[0].template[0].spec[0].container[0].resources[0].limits.memory == "256Mi"
    error_message = "EPP must declare a memory limit (default 256Mi) so it cannot OOM-pressure the node."
  }

  # MED: pod-level securityContext — non-root nobody user.
  assert {
    condition     = kubernetes_deployment.epp[0].spec[0].template[0].spec[0].security_context[0].run_as_non_root == true
    error_message = "EPP pod must run as non-root."
  }

  assert {
    condition     = kubernetes_deployment.epp[0].spec[0].template[0].spec[0].security_context[0].run_as_user == "65534"
    error_message = "EPP pod must run as uid 65534 (nobody)."
  }

  # MED: container-level securityContext — no escalation, read-only rootfs, drop ALL caps.
  assert {
    condition     = kubernetes_deployment.epp[0].spec[0].template[0].spec[0].container[0].security_context[0].allow_privilege_escalation == false
    error_message = "EPP container must not allow privilege escalation."
  }

  assert {
    condition     = kubernetes_deployment.epp[0].spec[0].template[0].spec[0].container[0].security_context[0].read_only_root_filesystem == true
    error_message = "EPP container must use a read-only root filesystem."
  }

  assert {
    condition     = contains(kubernetes_deployment.epp[0].spec[0].template[0].spec[0].container[0].security_context[0].capabilities[0].drop, "ALL")
    error_message = "EPP container must drop ALL Linux capabilities."
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

  # MED: TLS terminates at the WAF/ALB before Envoy (ADR-0047 D4); default tls_mode surfaced.
  assert {
    condition     = kubernetes_manifest.gateway[0].manifest.metadata.annotations["platform.aws/tls-mode"] == "terminate-at-lb"
    error_message = "Gateway must record tls_mode = terminate-at-lb (TLS terminates at the WAF/ALB, ADR-0047 D4)."
  }
}

run "waf_required_when_enabled" {
  command = plan

  variables {
    enabled         = true
    waf_web_acl_arn = ""
  }

  expect_failures = [
    var.waf_web_acl_arn,
  ]
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
