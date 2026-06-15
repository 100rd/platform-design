# ---------------------------------------------------------------------------------------------------------------------
# Tests for the talos-cluster module. The talos provider is mocked; assertions run at
# plan time over the double-gated bootstrap and the etcd-snapshot wiring (ADR-0049).
# ---------------------------------------------------------------------------------------------------------------------

mock_provider "talos" {}

run "default_posture_does_not_bootstrap" {
  command = plan

  # Default: enabled = false AND bootstrap_control_plane = false → no etcd init.
  assert {
    condition     = length(talos_machine_bootstrap.this) == 0
    error_message = "Default apply-gated posture must NOT create the etcd bootstrap resource."
  }

  assert {
    condition     = output.bootstrapped == false
    error_message = "bootstrapped output must be false in the default posture."
  }
}

run "enabled_but_not_bootstrap_flag_still_no_etcd_init" {
  command = plan

  variables {
    enabled                 = true
    bootstrap_control_plane = false
  }

  # The second gate keeps etcd untouched even when the module is otherwise enabled.
  assert {
    condition     = length(talos_machine_bootstrap.this) == 0
    error_message = "bootstrap_control_plane = false must prevent etcd init even when enabled = true."
  }
}

run "both_gates_true_creates_bootstrap" {
  command = plan

  variables {
    enabled                 = true
    bootstrap_control_plane = true
  }

  assert {
    condition     = length(talos_machine_bootstrap.this) == 1
    error_message = "Both gates true must create exactly one etcd bootstrap resource."
  }
}

run "etcd_snapshot_schedule_surfaced" {
  command = plan

  assert {
    condition     = length(output.etcd_snapshot_schedule) > 0
    error_message = "etcd snapshot schedule must be surfaced (ADR-0049 control-plane gate)."
  }
}

run "endpoint_carries_api_port" {
  command = plan

  assert {
    condition     = endswith(output.cluster_endpoint, ":6443")
    error_message = "cluster_endpoint must expose the Kubernetes API port."
  }
}
