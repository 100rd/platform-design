# ---------------------------------------------------------------------------------------------------------------------
# Tests for the baremetal-cilium-lb module. helm + kubernetes providers are mocked;
# assertions run at plan time over the CNI/LB/BGP wiring (ADR-0051).
# ---------------------------------------------------------------------------------------------------------------------

mock_provider "helm" {}
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
    condition     = length(helm_release.cilium) == 0
    error_message = "No Cilium release when enabled = false."
  }

  assert {
    condition     = length(kubernetes_manifest.lb_ip_pool) == 0
    error_message = "No LB-IPAM pool when enabled = false."
  }
}

run "deploys_cilium_and_lb_pool" {
  command = plan

  assert {
    condition     = helm_release.cilium[0].version == var.chart_version
    error_message = "Cilium must use the pinned chart version."
  }

  assert {
    condition     = length(kubernetes_manifest.lb_ip_pool) == 1
    error_message = "LB-IPAM pool must be created (no cloud LB on bare metal, ADR-0051)."
  }
}

run "kube_proxy_less_and_jumbo_mtu" {
  command = plan

  # ADR-0051 kube-proxy-less + ADR-0053 jumbo frames.
  assert {
    condition     = var.kube_proxy_replacement == "true"
    error_message = "Cilium must run kube-proxy-less (ADR-0051)."
  }

  assert {
    condition     = output.mtu == 9000
    error_message = "MTU must default to 9000 (jumbo frames) for the GPU fabric (ADR-0053)."
  }
}

run "bgp_peering_on_by_default" {
  command = plan

  assert {
    condition     = length(kubernetes_manifest.bgp_cluster_config) == 1
    error_message = "BGP cluster config must be created when enable_bgp (default true), ADR-0051."
  }

  # Runbook: hold timer raised so sessions survive CPU pressure.
  assert {
    condition     = kubernetes_manifest.bgp_peer_config[0].manifest.spec.timers.holdTimeSeconds == 180
    error_message = "BGP hold timer must be 180s per cilium-bgp-issues.md."
  }
}

run "bgp_off_falls_back_to_lb_only" {
  command = plan

  variables {
    enable_bgp = false
  }

  # LB-IPAM still allocates VIPs; BGP peering is not configured (L2 fallback, ADR-0051).
  assert {
    condition     = length(kubernetes_manifest.bgp_cluster_config) == 0
    error_message = "BGP cluster config must not be created when enable_bgp = false."
  }

  assert {
    condition     = length(kubernetes_manifest.lb_ip_pool) == 1
    error_message = "LB-IPAM pool must still exist in the BGP-off fallback path."
  }
}

run "bgp_hold_timer_floor_enforced" {
  command = plan

  variables {
    # Below the 90s floor → must fail (sessions drop under GPU load, cilium-bgp-issues runbook).
    bgp_hold_time_seconds = 60
  }

  expect_failures = [var.bgp_hold_time_seconds]
}
