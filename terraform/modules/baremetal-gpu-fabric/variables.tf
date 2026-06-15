variable "enabled" {
  description = "Master toggle. When false the module creates nothing (apply-gated default-OFF posture for the WS-A stack)."
  type        = bool
  default     = false
}

variable "namespace" {
  description = "Namespace into which the SR-IOV operator and fabric CRs are installed."
  type        = string
  default     = "sriov-network-operator"
}

variable "workload_namespace" {
  description = "Namespace GPU workloads run in (where the SriovNetwork / DRA claim template are attachable)."
  type        = string
  default     = "ml-workloads"
}

variable "fabric_path" {
  description = "Day-0 fabric delivery path. sriov = SR-IOV/RDMA device plugin (ADR-0053 day-0 primary). The DRANET path is additive and gated separately via enable_dranet."
  type        = string
  default     = "sriov"

  validation {
    condition     = contains(["sriov"], var.fabric_path)
    error_message = "fabric_path must be sriov (the ADR-0053 day-0 primary). DRANET is gated via enable_dranet."
  }
}

variable "fabric_mode" {
  description = "Physical fabric: infiniband (the UK doc's 400 Gbps IB + NVSwitch, ADR-0053 steady-state target) or roce (RoCEv2 Ethernet alternative)."
  type        = string
  default     = "infiniband"

  validation {
    condition     = contains(["infiniband", "roce"], var.fabric_mode)
    error_message = "fabric_mode must be one of infiniband, roce."
  }
}

variable "mtu" {
  description = "Fabric MTU. 9000 (jumbo frames) per the nic-tuning role (ADR-0053)."
  type        = number
  default     = 9000
}

variable "gpu_node_selector" {
  description = "Node selector restricting fabric components to GPU nodes."
  type        = map(string)
  default     = { "nvidia.com/gpu.present" = "true" }
  nullable    = false
}

variable "sriov_chart_version" {
  description = "Pinned SR-IOV Network Operator Helm chart version."
  type        = string
  default     = "1.3.0"
}

variable "sriov_chart_repository" {
  description = "Helm repository hosting the SR-IOV Network Operator chart."
  type        = string
  default     = "https://k8snetworkplumbingwg.github.io/sriov-network-operator"
}

variable "sriov_resource_name" {
  description = "Device-plugin resource name the RDMA VFs are advertised as (pods request this)."
  type        = string
  default     = "rdma_vf"
}

variable "sriov_num_vfs" {
  description = "Number of RDMA VFs to carve per GPU NIC."
  type        = number
  default     = 8
}

variable "sriov_nic_vendor" {
  description = "PCI vendor ID of the RDMA NIC (e.g. 15b3 = Mellanox/NVIDIA)."
  type        = string
  default     = "15b3"
}

variable "rdma_ip_range" {
  description = "IP range Whereabouts IPAM allocates to RDMA VF interfaces."
  type        = string
  default     = "192.168.100.0/24"
}

variable "enable_dranet" {
  description = "Enable the Cilium netdev DRA (mirror of DRANET) GATED TARGET path (ADR-0053 D3). Default false — only flip once DRA-netdev is GA on our Talos/k8s, a dranet release is validated on our NIC/kernel/image, and it matches the SR-IOV NCCL baseline."
  type        = bool
  default     = false
}

variable "dranet_device_class_name" {
  description = "DRA DeviceClass name for the RDMA NICs (DRANET path)."
  type        = string
  default     = "rdma-netdev"
}

variable "dranet_nic_count" {
  description = "Number of RDMA NICs per pod claim (DRANET path)."
  type        = number
  default     = 1
}

variable "helm_timeout" {
  description = "Helm release timeout in seconds."
  type        = number
  default     = 300
}

variable "platform_labels" {
  description = "ADR-0028 Kubernetes-plane labels (dotted keys, e.g. platform.system = ml-infra) applied to the namespace, SR-IOV operator, and all fabric custom resources."
  type        = map(string)
  default     = {}
  nullable    = false
}
