variable "enabled" {
  description = "Master toggle. When false the module creates nothing (apply-gated default-OFF posture for the WS-A stack)."
  type        = bool
  default     = false
}

variable "namespace" {
  description = "Namespace Cilium is installed into."
  type        = string
  default     = "kube-system"
}

variable "chart_version" {
  description = "Pinned Cilium Helm chart version."
  type        = string
  default     = "1.16.5"
}

variable "chart_repository" {
  description = "Helm repository hosting the Cilium chart."
  type        = string
  default     = "https://helm.cilium.io"
}

variable "kube_proxy_replacement" {
  description = "Cilium kube-proxy replacement mode (true = full eBPF datapath, ADR-0051 kube-proxy-less)."
  type        = string
  default     = "true"
}

variable "k8s_service_host" {
  description = "Kubernetes API host Cilium connects to (the control-plane VIP / KubePrism endpoint). Required in kube-proxy-less mode."
  type        = string
  default     = "localhost"
}

variable "k8s_service_port" {
  description = "Kubernetes API port (KubePrism local port by default)."
  type        = number
  default     = 7445
}

variable "mtu" {
  description = "Datapath MTU. 9000 (jumbo frames) for the GPU fabric per the nic-tuning role (ADR-0053)."
  type        = number
  default     = 9000
}

variable "operator_replicas" {
  description = "Number of Cilium operator replicas (HA on bare metal where there is no managed control plane)."
  type        = number
  default     = 2
}

variable "enable_bgp" {
  description = "Enable the Cilium BGP control-plane to advertise service VIPs to ToR switches (ADR-0051). When false, LB-IPAM still allocates VIPs but BGP peering is not configured (the MetalLB-L2-style fallback path)."
  type        = bool
  default     = true
}

variable "lb_ipam_cidrs" {
  description = "Service-VIP CIDR blocks LB-IPAM allocates from and advertises (no cloud LB hands these out)."
  type        = list(string)
  default     = ["10.20.0.0/24"]
  nullable    = false
}

variable "local_asn" {
  description = "Local BGP ASN the cluster peers from."
  type        = number
  default     = 64512
}

variable "bgp_peers" {
  description = "ToR switch BGP peers to advertise service VIPs to (ADR-0051)."
  type = list(object({
    name         = string
    peer_address = string
    peer_asn     = number
  }))
  default = [
    { name = "tor-1", peer_address = "10.10.255.1", peer_asn = 64513 },
    { name = "tor-2", peer_address = "10.10.255.2", peer_asn = 64513 },
  ]
  nullable = false
}

variable "bgp_hold_time_seconds" {
  description = "BGP hold timer. Raised (180s) per cilium-bgp-issues.md so sessions survive CPU pressure on GPU nodes."
  type        = number
  default     = 180

  validation {
    condition     = var.bgp_hold_time_seconds >= 90
    error_message = "BGP hold timer must be >= 90s to avoid session drops under GPU load (see cilium-bgp-issues runbook)."
  }
}

variable "bgp_keepalive_time_seconds" {
  description = "BGP keepalive timer (typically hold/3)."
  type        = number
  default     = 60
}

variable "bgp_ebgp_multihop" {
  description = "eBGP multihop count for ToR peering."
  type        = number
  default     = 1
}

variable "helm_timeout" {
  description = "Helm release timeout in seconds."
  type        = number
  default     = 600
}

variable "platform_labels" {
  description = "ADR-0028 Kubernetes-plane labels (dotted keys, e.g. platform.system = ml-infra) applied to Cilium workloads and the LB/BGP custom resources."
  type        = map(string)
  default     = {}
  nullable    = false
}
