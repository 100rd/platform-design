# ---------------------------------------------------------------------------------------------------------------------
# Bare-metal Cilium CNI + LB-IPAM + BGP Module (WS-A — ml-infra) — ADR-0051
# ---------------------------------------------------------------------------------------------------------------------
# Deploys Cilium as the CNI in kube-proxy-less mode and provides the bare-metal
# load-balancer that does NOT come for free on owned hardware (no cloud VPC, no cloud LB,
# ADR-0051): LB-IPAM hands out service VIPs and the Cilium BGP control-plane advertises
# them to the ToR switches.
#
# The CiliumLoadBalancerIPPool / CiliumBGPClusterConfig CRs require the CRDs to exist on a
# live cluster, so they are emitted as kubernetes_manifest (mocked in tftest) — same
# pattern as the gke-gpu-fabric module. BGP timers honour the cilium-bgp-issues.md runbook
# (hold-timer raised under CPU pressure, ToR max-prefix sized).
#
# ADR-0028: namespace + Helm workloads + CRs carry the Kubernetes-plane dotted labels.
# ---------------------------------------------------------------------------------------------------------------------

locals {
  platform_labels = merge(
    {
      "platform.system"     = "ml-infra"
      "platform.component"  = "networking"
      "platform.managed-by" = "terragrunt"
    },
    var.platform_labels,
  )

  enable_bgp = var.enabled && var.enable_bgp

  gpu_tolerations = [
    {
      key      = "nvidia.com/gpu"
      operator = "Exists"
      effect   = "NoSchedule"
    }
  ]
}

# ---------------------------------------------------------------------------------------------------------------------
# Cilium Helm release — CNI in kube-proxy-less mode + LB-IPAM + BGP control-plane.
# ---------------------------------------------------------------------------------------------------------------------

resource "helm_release" "cilium" {
  count = var.enabled ? 1 : 0

  name       = "cilium"
  repository = var.chart_repository
  chart      = "cilium"
  version    = var.chart_version
  namespace  = var.namespace
  timeout    = var.helm_timeout

  values = [
    yamlencode({
      # kube-proxy-less: Cilium owns the service datapath (eBPF), ADR-0051.
      kubeProxyReplacement = var.kube_proxy_replacement
      k8sServiceHost       = var.k8s_service_host
      k8sServicePort       = var.k8s_service_port

      # MTU 9000 (jumbo frames) for the GPU fabric (nic-tuning role, ADR-0053).
      MTU = var.mtu

      bgpControlPlane = {
        enabled = var.enable_bgp
      }

      # LB-IPAM advertises service VIPs over the physical network (no cloud LB).
      loadBalancer = {
        algorithm = "maglev"
      }

      operator = {
        replicas    = var.operator_replicas
        podLabels   = local.platform_labels
        tolerations = local.gpu_tolerations
      }

      # ADR-0028 labels on the agent pods.
      podLabels = local.platform_labels
    })
  ]
}

# ---------------------------------------------------------------------------------------------------------------------
# LB-IPAM pool — the service-VIP address pool advertised to the outside world.
# ---------------------------------------------------------------------------------------------------------------------

resource "kubernetes_manifest" "lb_ip_pool" {
  count = var.enabled ? 1 : 0

  manifest = {
    apiVersion = "cilium.io/v2alpha1"
    kind       = "CiliumLoadBalancerIPPool"
    metadata = {
      name   = "service-vip-pool"
      labels = local.platform_labels
    }
    spec = {
      blocks = [for cidr in var.lb_ipam_cidrs : { cidr = cidr }]
    }
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# BGP cluster config — peer with the ToR switches; runbook-honouring timers.
# Gated by enable_bgp (MetalLB-L2-style fallback documented in ADR-0051 when off).
# ---------------------------------------------------------------------------------------------------------------------

resource "kubernetes_manifest" "bgp_cluster_config" {
  count = local.enable_bgp ? 1 : 0

  manifest = {
    apiVersion = "cilium.io/v2alpha1"
    kind       = "CiliumBGPClusterConfig"
    metadata = {
      name   = "tor-peering"
      labels = local.platform_labels
    }
    spec = {
      nodeSelector = {
        matchLabels = {
          "platform.system" = "ml-infra"
        }
      }
      bgpInstances = [
        {
          name     = "instance-${var.local_asn}"
          localASN = var.local_asn
          peers = [for p in var.bgp_peers : {
            name        = p.name
            peerAddress = p.peer_address
            peerASN     = p.peer_asn
            peerConfigRef = {
              name = "tor-peer-config"
            }
          }]
        }
      ]
    }
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# BGP peer config — hold/keepalive timers per cilium-bgp-issues.md (hold raised under load).
# ---------------------------------------------------------------------------------------------------------------------

resource "kubernetes_manifest" "bgp_peer_config" {
  count = local.enable_bgp ? 1 : 0

  manifest = {
    apiVersion = "cilium.io/v2alpha1"
    kind       = "CiliumBGPPeerConfig"
    metadata = {
      name   = "tor-peer-config"
      labels = local.platform_labels
    }
    spec = {
      timers = {
        holdTimeSeconds      = var.bgp_hold_time_seconds
        keepAliveTimeSeconds = var.bgp_keepalive_time_seconds
      }
      ebgpMultihop = var.bgp_ebgp_multihop
      gracefulRestart = {
        enabled = true
      }
    }
  }
}
