# ---------------------------------------------------------------------------------------------------------------------
# Talos MachineConfig Module (WS-A — ml-infra) — ADR-0049 / ADR-0050 / ADR-0052
# ---------------------------------------------------------------------------------------------------------------------
# Renders immutable Talos Linux MachineConfig for two machine classes — control-plane
# and GPU-worker — via the siderolabs/talos provider. This is the SINGLE place where
# OS-level prerequisites that cannot be installed on a running immutable host are
# declared, because Talos has no shell, no SSH, and no package manager (ADR-0049):
#
#   * machine.kernel.modules  — `rbd` + `ceph` are the HARD Rook-Ceph RBD prerequisite
#                               (ADR-0052): without them csi-rbdplugin crash-loops and
#                               no RBD PVC will ever mount. `nvidia` / `nvidia_uvm` etc.
#                               back the GPU system extension (ADR-0050).
#   * system extensions       — the NVIDIA driver (`nonfree-kmod-nvidia` +
#                               `nvidia-container-toolkit`) ships in the boot image as a
#                               Talos system extension, never `apt install` (ADR-0050).
#   * machine.nodeLabels      — ADR-0028 dotted platform labels onto every node.
#   * KubePrism + no-SSH/mTLS  — in-cluster API HA + the immutable security posture.
#
# This module is the explicit replacement for the kubeadm `hetzner-kubeadm.sh` host
# bootstrap script — there is NO host bootstrap here. It is apply-gated and default
# rendering-only: `talos_machine_secrets` is created when var.enabled, and the
# configuration data sources render config; nothing is applied to a machine (no
# talos_machine_configuration_apply, no talos_machine_bootstrap — those live in the
# talos-cluster module and stay apply-gated).
#
# ADR-0028: K8s/Talos plane uses DOTTED label keys (platform.system = ml-infra).
# ---------------------------------------------------------------------------------------------------------------------

locals {
  # ADR-0028 Talos/Kubernetes-plane baseline node labels for the ml-infra system.
  platform_node_labels = merge(
    {
      "platform.system"     = "ml-infra"
      "platform.component"  = "compute"
      "platform.managed-by" = "terragrunt"
    },
    var.platform_labels,
  )

  # GPU-worker nodes additionally advertise the GPU-present label so the GPU Operator
  # device-plugin and DCGM DaemonSet (baremetal-gpu-operator / -dcgm) select them.
  gpu_worker_node_labels = merge(
    local.platform_node_labels,
    {
      "nvidia.com/gpu.present" = "true"
    },
  )

  # HARD prerequisites that can only be declared here on immutable Talos:
  #   * rbd + ceph   — Rook-Ceph RBD CSI (ADR-0052), load-bearing for any RBD PVC.
  #   * nvidia*      — back the NVIDIA system-extension driver (ADR-0050) on GPU workers.
  # Control-plane nodes need rbd/ceph too (Ceph mons/CSI may schedule there) but no nvidia.
  control_plane_kernel_modules = concat(
    [for m in var.ceph_kernel_modules : { name = m }],
    [for m in var.extra_kernel_modules : { name = m }],
  )

  gpu_worker_kernel_modules = concat(
    [for m in var.ceph_kernel_modules : { name = m }],
    [for m in var.nvidia_kernel_modules : { name = m }],
    [for m in var.extra_kernel_modules : { name = m }],
  )
}

# ---------------------------------------------------------------------------------------------------------------------
# Machine secrets — the PKI/secret bundle a Talos cluster is rendered against.
# Gated by var.enabled. NOTE: the bundle is sensitive and lives in state; in real use it
# is sourced from / persisted to a secret manager, never committed (repo rule: no secrets
# in code/state). Apply-gated like the rest of WS-A.
# ---------------------------------------------------------------------------------------------------------------------

resource "talos_machine_secrets" "this" {
  count = var.enabled ? 1 : 0

  talos_version = var.talos_version
}

# ---------------------------------------------------------------------------------------------------------------------
# Control-plane MachineConfig — etcd + API server; KubePrism; rbd/ceph kernel modules.
# ---------------------------------------------------------------------------------------------------------------------

data "talos_machine_configuration" "controlplane" {
  count = var.enabled ? 1 : 0

  cluster_name       = var.cluster_name
  cluster_endpoint   = var.cluster_endpoint
  machine_type       = "controlplane"
  machine_secrets    = talos_machine_secrets.this[0].machine_secrets
  talos_version      = var.talos_version
  kubernetes_version = var.kubernetes_version

  config_patches = [
    yamlencode({
      machine = {
        # ADR-0050/0052: kernel modules declared at the OS layer (immutable host).
        kernel = {
          modules = local.control_plane_kernel_modules
        }
        # ADR-0028 node labels.
        nodeLabels = local.platform_node_labels
        # Immutable-OS posture: KubePrism for in-cluster API HA (ADR-0049 / WS-E control).
        features = {
          kubePrism = {
            enabled = var.kube_prism_enabled
            port    = var.kube_prism_port
          }
        }
        install = {
          disk  = var.install_disk
          image = var.talos_installer_image
          wipe  = false
        }
      }
    }),
  ]
}

# ---------------------------------------------------------------------------------------------------------------------
# GPU-worker MachineConfig — NVIDIA system extension + rbd/ceph + nvidia kernel modules
# + the Rook kubelet extra-mounts / sysctls / open-file limits.
# ---------------------------------------------------------------------------------------------------------------------

data "talos_machine_configuration" "gpu_worker" {
  count = var.enabled ? 1 : 0

  cluster_name       = var.cluster_name
  cluster_endpoint   = var.cluster_endpoint
  machine_type       = "worker"
  machine_secrets    = talos_machine_secrets.this[0].machine_secrets
  talos_version      = var.talos_version
  kubernetes_version = var.kubernetes_version

  config_patches = [
    yamlencode({
      machine = {
        # ADR-0050/0052: rbd+ceph (Rook RBD prereq) AND nvidia* (GPU driver) modules.
        kernel = {
          modules = local.gpu_worker_kernel_modules
        }
        # ADR-0028 + GPU-present label so device-plugin/DCGM select these nodes.
        nodeLabels = local.gpu_worker_node_labels
        # KubePrism on workers too.
        features = {
          kubePrism = {
            enabled = var.kube_prism_enabled
            port    = var.kube_prism_port
          }
        }
        install = {
          disk  = var.install_disk
          image = var.talos_installer_image
          wipe  = false
          # ADR-0050: the NVIDIA driver ships as a Talos system extension baked into
          # the boot image — never installed on a running host.
          extensions = [for ext in var.system_extensions : { image = ext }]
        }
        # ADR-0052: Rook-Ceph requires the kubelet to mount the host /var/lib/rook path
        # and raise open-file limits / sysctls; declared here because the host is immutable.
        kubelet = {
          extraMounts = var.rook_kubelet_extra_mounts
        }
        sysctls = var.gpu_worker_sysctls
      }
    }),
  ]
}

# ---------------------------------------------------------------------------------------------------------------------
# Client configuration — talosctl mTLS client config (the ONLY access path; no SSH).
# ---------------------------------------------------------------------------------------------------------------------

data "talos_client_configuration" "this" {
  count = var.enabled ? 1 : 0

  cluster_name         = var.cluster_name
  client_configuration = talos_machine_secrets.this[0].client_configuration
  endpoints            = var.control_plane_endpoints
  nodes                = var.control_plane_endpoints
}
