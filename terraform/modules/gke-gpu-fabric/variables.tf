variable "enabled" {
  description = "Deploy the GPUDirect-TCPX/TCPXO fabric objects. Set false to no-op."
  type        = bool
  default     = true
  nullable    = false
}

variable "mode" {
  description = "GPUDirect mode: tcpx (a3-highgpu-8g, 4 NICs) or tcpxo (a3-megagpu-8g, 8 NICs)."
  type        = string
  default     = "tcpx"

  validation {
    condition     = contains(["tcpx", "tcpxo"], var.mode)
    error_message = "mode must be tcpx or tcpxo."
  }
}

variable "data_plane_networks" {
  description = "Data-plane VPCs to wire (one GKENetworkParamSet + Network each). 4 entries for TCPX, 8 for TCPXO."
  type = list(object({
    name       = string # short k8s object name, e.g. gpu-dp-0
    network    = string # GCP VPC name
    subnetwork = string # GCP subnet name
  }))
  default = []
}

variable "namespace" {
  description = "Namespace for the NCCL installer DaemonSet."
  type        = string
  default     = "kube-system"
}

variable "tcpx_installer_image" {
  description = "Pinned NCCL GPUDirect-TCPX plugin installer image (a3-high). Pin a real ?ref/tag at apply time."
  type        = string
  default     = "us-docker.pkg.dev/gce-ai-infra/gpudirect-tcpx/nccl-plugin-gpudirecttcpx-dev:v3.1.10"
}

variable "tcpxo_installer_image" {
  description = "Pinned NCCL GPUDirect-TCPXO plugin installer image (a3-mega). Pin a real tag at apply time."
  type        = string
  default     = "us-docker.pkg.dev/gce-ai-infra/gpudirect-tcpxo/nccl-plugin-gpudirecttcpxo-dev:v1.0.8"
}

variable "pause_image" {
  description = "Pause/sleep image for the installer DaemonSet's keep-alive container."
  type        = string
  default     = "registry.k8s.io/pause:3.10"
}

variable "platform_labels" {
  description = "Additional ADR-0028 Kubernetes-plane platform labels (dotted keys)."
  type        = map(string)
  default     = {}
}
