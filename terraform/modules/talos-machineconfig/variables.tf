variable "enabled" {
  description = "Master toggle. When false the module renders/creates nothing (apply-gated: default-OFF posture for the WS-A stack so nothing provisions real infra)."
  type        = bool
  default     = false
}

variable "cluster_name" {
  description = "Talos cluster name (per-DC, e.g. uk-primary / uk-standby). Carried into the rendered MachineConfig and client configuration."
  type        = string
  default     = "uk-baremetal-gpu"
}

variable "cluster_endpoint" {
  description = "Kubernetes API endpoint URL the control plane advertises (the control-plane VIP), e.g. https://10.10.0.10:6443. Apply-gated; mock at plan time."
  type        = string
  default     = "https://10.10.0.10:6443"
}

variable "control_plane_endpoints" {
  description = "List of control-plane node IPs/hostnames the talosctl client targets (mTLS machine API — the only access path, no SSH)."
  type        = list(string)
  default     = ["10.10.0.10"]
  nullable    = false
}

variable "talos_version" {
  description = "Talos Linux release the MachineConfig and secrets bundle are rendered for. Pin explicitly per environment (ADR-0050: extension is coupled to the Talos release)."
  type        = string
  default     = "v1.9.2"
}

variable "kubernetes_version" {
  description = "Kubernetes version pin rendered into the MachineConfig."
  type        = string
  default     = "v1.32.0"
}

variable "install_disk" {
  description = "Block device Talos installs to (immutable A/B install target). Bare-metal-specific; set per hardware profile."
  type        = string
  default     = "/dev/nvme0n1"
}

variable "talos_installer_image" {
  description = "Talos installer image (boot image) that bakes in the system extensions. Pin to the Talos release per ADR-0050."
  type        = string
  default     = "ghcr.io/siderolabs/installer:v1.9.2"
}

variable "system_extensions" {
  description = "Talos system-extension image refs baked into the GPU-worker boot image (ADR-0050). Default ships the NVIDIA nonfree kmod driver + container toolkit — the immutable-OS replacement for a host driver install."
  type        = list(string)
  default = [
    "ghcr.io/siderolabs/nonfree-kmod-nvidia:535.183.06-v1.9.2",
    "ghcr.io/siderolabs/nvidia-container-toolkit:535.183.06-v1.17.3",
  ]
  nullable = false
}

variable "ceph_kernel_modules" {
  description = "Kernel modules required by Rook-Ceph RBD CSI (ADR-0052). HARD prerequisite: rbd + ceph MUST be present on every node or csi-rbdplugin crash-loops and no RBD PVC mounts. Declared here because Talos is immutable and modules cannot be loaded on a running host."
  type        = list(string)
  default     = ["rbd", "ceph"]
  nullable    = false

  validation {
    condition     = contains(var.ceph_kernel_modules, "rbd") && contains(var.ceph_kernel_modules, "ceph")
    error_message = "ceph_kernel_modules MUST include both 'rbd' and 'ceph' — they are the load-bearing Rook-Ceph RBD prerequisite (ADR-0052)."
  }
}

variable "nvidia_kernel_modules" {
  description = "Kernel modules backing the NVIDIA system-extension driver on GPU workers (ADR-0050)."
  type        = list(string)
  default     = ["nvidia", "nvidia_uvm", "nvidia_drm", "nvidia_modeset"]
  nullable    = false
}

variable "extra_kernel_modules" {
  description = "Additional kernel modules to load on all nodes (e.g. fabric/RDMA modules). Appended to the ceph (+ nvidia on workers) set."
  type        = list(string)
  default     = []
  nullable    = false
}

variable "kube_prism_enabled" {
  description = "Enable Talos KubePrism for in-cluster Kubernetes API HA (ADR-0049; a WS-E posture control). No managed control plane to fall back on, so KubePrism is on by default."
  type        = bool
  default     = true
}

variable "kube_prism_port" {
  description = "Port KubePrism listens on for the in-cluster API load-balanced endpoint."
  type        = number
  default     = 7445
}

variable "rook_kubelet_extra_mounts" {
  description = "Talos kubelet extraMounts entries so Rook-Ceph can bind-mount its host state path (ADR-0052). Required on immutable Talos where /var/lib/rook is not writable by default."
  type = list(object({
    destination = string
    type        = string
    source      = string
    options     = list(string)
  }))
  default = [
    {
      destination = "/var/lib/rook"
      type        = "bind"
      source      = "/var/lib/rook"
      options     = ["bind", "rshared", "rw"]
    },
  ]
  nullable = false
}

variable "gpu_worker_sysctls" {
  description = "Kernel sysctls applied to GPU-worker nodes (e.g. open-file limits / network buffers for Rook-Ceph and the RDMA fabric, ADR-0052/0053)."
  type        = map(string)
  default = {
    "fs.inotify.max_user_instances" = "8192"
    "fs.inotify.max_user_watches"   = "524288"
    "net.core.rmem_max"             = "16777216"
    "net.core.wmem_max"             = "16777216"
  }
  nullable = false
}

variable "platform_labels" {
  description = "ADR-0028 Talos/Kubernetes-plane node labels (DOTTED keys, e.g. platform.system = ml-infra). Merged onto every node's machine.nodeLabels; pass platform.env / platform.owner here."
  type        = map(string)
  default     = {}
  nullable    = false
}
