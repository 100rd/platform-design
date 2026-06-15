# ---------------------------------------------------------------------------------------------------------------------
# Tests for the talos-machineconfig module.
# The siderolabs/talos provider is mocked so no real machine, secrets bundle, or
# credentials are needed; assertions run at plan time over the module's wiring,
# toggles, and the load-bearing ADR-0052 rbd+ceph kernel-module prerequisite.
# ---------------------------------------------------------------------------------------------------------------------

mock_provider "talos" {}

variables {
  enabled = true
  platform_labels = {
    "platform.env"   = "staging"
    "platform.owner" = "team-data"
  }
}

run "disabled_by_default_creates_nothing" {
  command = plan

  variables {
    enabled = false
  }

  assert {
    condition     = length(talos_machine_secrets.this) == 0
    error_message = "Apply-gated default OFF: no machine secrets should be created when enabled = false."
  }

  assert {
    condition     = length(data.talos_machine_configuration.controlplane) == 0
    error_message = "No control-plane config should render when enabled = false."
  }
}

run "renders_both_machine_classes_when_enabled" {
  command = plan

  assert {
    condition     = length(data.talos_machine_configuration.controlplane) == 1
    error_message = "Control-plane MachineConfig must render when enabled = true."
  }

  assert {
    condition     = length(data.talos_machine_configuration.gpu_worker) == 1
    error_message = "GPU-worker MachineConfig must render when enabled = true."
  }

  assert {
    condition     = length(talos_machine_secrets.this) == 1
    error_message = "Machine secrets bundle must be created when enabled = true."
  }
}

run "rbd_and_ceph_kernel_modules_present" {
  command = plan

  # ADR-0052 load-bearing gate: rbd + ceph must be in the worker kernel-module set or
  # csi-rbdplugin crash-loops and no RBD PVC ever mounts.
  assert {
    condition     = contains([for m in local.gpu_worker_kernel_modules : m.name], "rbd")
    error_message = "GPU-worker kernel modules MUST include rbd (Rook-Ceph RBD prerequisite, ADR-0052)."
  }

  assert {
    condition     = contains([for m in local.gpu_worker_kernel_modules : m.name], "ceph")
    error_message = "GPU-worker kernel modules MUST include ceph (Rook-Ceph RBD prerequisite, ADR-0052)."
  }

  assert {
    condition     = contains([for m in local.control_plane_kernel_modules : m.name], "rbd")
    error_message = "Control-plane kernel modules MUST also include rbd (Ceph mons/CSI may schedule there, ADR-0052)."
  }
}

run "nvidia_driver_extension_and_modules_on_workers" {
  command = plan

  # ADR-0050: the NVIDIA driver ships as a Talos system extension, never a host install.
  assert {
    condition     = length(var.system_extensions) > 0
    error_message = "GPU workers must declare at least one NVIDIA system extension (ADR-0050)."
  }

  assert {
    condition     = contains([for m in local.gpu_worker_kernel_modules : m.name], "nvidia")
    error_message = "GPU-worker kernel modules must include the nvidia module backing the system extension (ADR-0050)."
  }

  # Control-plane must NOT carry nvidia modules (no GPU there).
  assert {
    condition     = !contains([for m in local.control_plane_kernel_modules : m.name], "nvidia")
    error_message = "Control-plane nodes should not load nvidia modules."
  }
}

run "adr0028_node_labels_and_kubeprism" {
  command = plan

  assert {
    condition     = local.platform_node_labels["platform.system"] == "ml-infra"
    error_message = "Nodes must carry platform.system = ml-infra per ADR-0028."
  }

  assert {
    condition     = local.platform_node_labels["platform.env"] == "staging"
    error_message = "Caller-supplied platform.env label must merge onto node labels."
  }

  assert {
    condition     = local.gpu_worker_node_labels["nvidia.com/gpu.present"] == "true"
    error_message = "GPU workers must advertise nvidia.com/gpu.present so device-plugin/DCGM select them."
  }

  assert {
    condition     = var.kube_prism_enabled
    error_message = "KubePrism must default ON for in-cluster API HA (ADR-0049)."
  }
}
