# ---------------------------------------------------------------------------------------------------------------------
# Tests for the talos-gpu-nodepool module. The kubernetes provider is mocked; assertions
# run at plan time over the fixed-capacity (no-autoscaler) intent and the gated
# Cluster-API re-image path (ADR-0054).
# ---------------------------------------------------------------------------------------------------------------------

mock_provider "kubernetes" {}

variables {
  enabled   = true
  pool_name = "h100-training"
  gpu_model = "H100"
  machines = [
    { name = "gpu-01" },
    { name = "gpu-02" },
    { name = "gpu-03" },
  ]
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
    condition     = length(kubernetes_manifest.nodepool_policy) == 0
    error_message = "No node-pool policy should be created when enabled = false."
  }
}

run "fixed_capacity_equals_machine_count" {
  command = plan

  # ADR-0054: capacity is the machine count, NOT an autoscaling range.
  assert {
    condition     = output.fixed_capacity == 3
    error_message = "Fixed capacity must equal the number of machines (no autoscaler, ADR-0054)."
  }

  assert {
    condition     = kubernetes_manifest.nodepool_policy[0].manifest.data.autoscaling == "disabled"
    error_message = "Node-pool policy must explicitly mark autoscaling disabled (ADR-0054)."
  }
}

run "gpu_labels_and_taint" {
  command = plan

  assert {
    condition     = output.node_labels["nvidia.com/gpu.present"] == "true"
    error_message = "Pool nodes must advertise nvidia.com/gpu.present."
  }

  assert {
    condition     = output.node_labels["platform.system"] == "ml-infra"
    error_message = "Pool nodes must carry platform.system = ml-infra (ADR-0028)."
  }

  assert {
    condition     = output.gpu_taint == "nvidia.com/gpu=present:NoSchedule"
    error_message = "GPU taint must be applied so only GPU workloads schedule on the pool."
  }
}

run "cluster_api_off_by_default" {
  command = plan

  # manage_cluster_api defaults false → static pool, no Machine objects reconcile hardware.
  assert {
    condition     = length(kubernetes_manifest.cluster_api_machine) == 0
    error_message = "Cluster-API Machine objects must be OFF by default (static pool, ADR-0054)."
  }

  assert {
    condition     = output.cluster_api_managed == false
    error_message = "cluster_api_managed must be false by default."
  }
}

run "cluster_api_machines_when_enabled" {
  command = plan

  variables {
    manage_cluster_api = true
    machines = [
      { name = "gpu-01", bootstrap_secret = "gpu-01-bootstrap" },
      { name = "gpu-02", bootstrap_secret = "gpu-02-bootstrap" },
    ]
  }

  assert {
    condition     = length(kubernetes_manifest.cluster_api_machine) == 2
    error_message = "One Cluster-API Machine per machine should be created when manage_cluster_api = true."
  }
}
