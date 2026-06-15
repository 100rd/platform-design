variable "enabled" {
  description = "Master toggle. When false the module creates nothing (apply-gated default-OFF posture for the WS-A stack)."
  type        = bool
  default     = false
}

variable "namespace" {
  description = "Namespace Rook-Ceph runs in."
  type        = string
  default     = "rook-ceph"
}

variable "ceph_kernel_modules" {
  description = "The kernel modules talos-machineconfig declared (wired from its output via the stack dependency). HARD ADR-0052 contract: must include rbd + ceph or csi-rbdplugin crash-loops and no RBD PVC mounts. The validation below fails the plan if they are absent — enforcing the load-bearing dependency in code."
  type        = list(string)
  default     = ["rbd", "ceph"]
  nullable    = false

  validation {
    condition     = contains(var.ceph_kernel_modules, "rbd") && contains(var.ceph_kernel_modules, "ceph")
    error_message = "Rook-Ceph requires the rbd + ceph kernel modules to be declared in talos-machineconfig (ADR-0052) — without them csi-rbdplugin crash-loops and no RBD PVC will mount."
  }
}

variable "chart_version" {
  description = "Pinned Rook-Ceph operator Helm chart version."
  type        = string
  default     = "v1.15.6"
}

variable "chart_repository" {
  description = "Helm repository hosting the rook-ceph chart."
  type        = string
  default     = "https://charts.rook.io/release"
}

variable "ceph_image" {
  description = "Ceph container image the CephCluster runs."
  type        = string
  default     = "quay.io/ceph/ceph:v18.2.4"
}

variable "data_dir_host_path" {
  description = "Host path Rook persists Ceph state to. Must match the talos-machineconfig kubelet extraMount (ADR-0052)."
  type        = string
  default     = "/var/lib/rook"
}

variable "mon_count" {
  description = "Number of Ceph monitors (odd number for quorum; 3 is the replicated default)."
  type        = number
  default     = 3

  validation {
    condition     = var.mon_count % 2 == 1
    error_message = "mon_count must be odd for quorum (e.g. 3 or 5)."
  }
}

variable "block_pool_replicas" {
  description = "Replication factor for the RBD/FS/object pools (≥3 to survive a node loss; R5 mitigation)."
  type        = number
  default     = 3

  validation {
    condition     = var.block_pool_replicas >= 3
    error_message = "block_pool_replicas must be >= 3 to survive a node loss (storage-SPOF mitigation, ADR-0052 / risk R5)."
  }
}

variable "use_all_nodes" {
  description = "Let Ceph use all nodes for OSDs."
  type        = bool
  default     = true
}

variable "use_all_devices" {
  description = "Let Ceph consume all available block devices for OSDs."
  type        = bool
  default     = false
}

variable "enable_filesystem" {
  description = "Create a CephFilesystem (RWX) for shared datasets."
  type        = bool
  default     = true
}

variable "enable_object_store" {
  description = "Create a CephObjectStore (RGW S3) — the optional S3-compatible artifact-store backend for WS-B (ADR-0052)."
  type        = bool
  default     = true
}

variable "object_store_name" {
  description = "Name of the Ceph RGW object store."
  type        = string
  default     = "ml-artifacts"
}

variable "rgw_port" {
  description = "Port the RGW S3 gateway listens on."
  type        = number
  default     = 80
}

variable "rgw_instances" {
  description = "Number of RGW gateway instances (HA)."
  type        = number
  default     = 2
}

variable "helm_timeout" {
  description = "Helm release timeout in seconds."
  type        = number
  default     = 600
}

variable "platform_labels" {
  description = "ADR-0028 Kubernetes-plane labels (dotted keys, e.g. platform.system = ml-infra) applied to the namespace, operator, and all Ceph custom resources."
  type        = map(string)
  default     = {}
  nullable    = false
}
