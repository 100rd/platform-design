# ---------------------------------------------------------------------------------------------------------------------
# Talos Cluster Bootstrap Module (WS-A — ml-infra) — ADR-0049
# ---------------------------------------------------------------------------------------------------------------------
# Bootstraps the self-operated Talos control plane: etcd init, kubeconfig retrieval, and
# the etcd-snapshot schedule wiring. Unlike GKE/EKS there is NO managed control plane —
# we own etcd and the API server (ADR-0049), so this module owns the control-plane VIP /
# KubePrism endpoint and the snapshot cadence that the WS-A acceptance and the
# control-plane-change gate (etcd snapshot before every control-plane MachineConfig
# change) depend on.
#
# Consumes the secrets + endpoint produced by talos-machineconfig via input variables
# (wired through a `dependency` block at the stack layer).
#
# Apply-gated / default-OFF: talos_machine_bootstrap actually initialises etcd on a live
# node — it is created ONLY when both var.enabled AND var.bootstrap_control_plane are
# true, so the default stack posture provisions nothing. No bootstrap is ever run in this
# repo (mock/emulation, plan-only).
#
# ADR-0028: dotted platform labels surfaced via outputs for downstream K8s resources.
# ---------------------------------------------------------------------------------------------------------------------

locals {
  platform_labels = merge(
    {
      "platform.system"     = "ml-infra"
      "platform.component"  = "control-plane"
      "platform.managed-by" = "terragrunt"
    },
    var.platform_labels,
  )

  do_bootstrap = var.enabled && var.bootstrap_control_plane
}

# ---------------------------------------------------------------------------------------------------------------------
# etcd init / control-plane bootstrap — runs ONCE against the first control-plane node.
# Double-gated (enabled AND bootstrap_control_plane) so the default posture never touches
# a machine. Apply-gated: in this repo it is plan-only.
# ---------------------------------------------------------------------------------------------------------------------

resource "talos_machine_bootstrap" "this" {
  count = local.do_bootstrap ? 1 : 0

  node                 = var.bootstrap_node
  endpoint             = var.control_plane_vip
  client_configuration = var.client_configuration
}

# ---------------------------------------------------------------------------------------------------------------------
# Cluster kubeconfig — retrieved after bootstrap; consumed by every in-cluster unit
# (cilium-lb, rook-ceph, gpu-operator, …) via the stack `dependency` wiring.
# ---------------------------------------------------------------------------------------------------------------------

resource "talos_cluster_kubeconfig" "this" {
  count = local.do_bootstrap ? 1 : 0

  node                 = var.bootstrap_node
  endpoint             = var.control_plane_vip
  client_configuration = var.client_configuration

  depends_on = [talos_machine_bootstrap.this]
}
