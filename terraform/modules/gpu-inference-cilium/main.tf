# ---------------------------------------------------------------------------------------------------------------------
# GPU Inference Cilium v1.19 — Native Routing + BGP Control Plane
# ---------------------------------------------------------------------------------------------------------------------
# Deploys Cilium v1.19 in native-routing mode with BGP Control Plane peering
# to AWS Transit Gateway Connect. Pods get IPs from cluster-pool CIDR
# (100.64.0.0/10), not VPC. Each node is a BGP speaker announcing its Pod CIDR
# to TGW, enabling near-physical-network latency for NCCL/distributed training.
# ---------------------------------------------------------------------------------------------------------------------

resource "helm_release" "cilium" {
  name             = "cilium"
  repository       = "https://helm.cilium.io/"
  chart            = "cilium"
  version          = var.cilium_version
  namespace        = "kube-system"
  create_namespace = false

  wait          = true
  wait_for_jobs = true
  timeout       = 600

  values = [
    yamlencode({
      # Native routing mode — no VXLAN/Geneve encapsulation
      routingMode           = "native"
      autoDirectNodeRoutes  = true
      ipv4NativeRoutingCIDR = var.pod_cidr

      # Cluster-pool IPAM (pods get IPs from 100.64.0.0/10, not VPC)
      ipam = {
        mode = "cluster-pool"
        operator = {
          clusterPoolIPv4PodCIDRList = [var.pod_cidr]
          clusterPoolIPv4MaskSize    = var.pod_cidr_mask_size
        }
      }

      # kube-proxy replacement via eBPF
      kubeProxyReplacement = true
      k8sServiceHost       = var.cluster_endpoint
      k8sServicePort       = 443

      # BPF settings
      bpf = {
        masquerade   = true
        lbMapMax     = tonumber(var.bpf_lb_map_max)
        policyMapMax = tonumber(var.bpf_policy_map_max)
      }

      # No conntrack iptables rules — eBPF handles it
      installNoConntrackIptablesRules = true

      # Disable L7 proxy for GPU traffic — adds latency
      l7Proxy = false

      # Socket-level acceleration for node-local traffic
      sockops = {
        enabled = true
      }

      # EDT-based bandwidth management
      bandwidthManager = {
        enabled = true
      }

      # BGP Control Plane
      bgpControlPlane = {
        enabled = true
      }

      # EndpointSlice for 5000-node scale
      endpointSlice = {
        enabled = true
      }

      # Hubble observability
      hubble = {
        enabled = true
        relay = {
          enabled = true
        }
        ui = {
          enabled = false
        }
      }

      # Operator tuning for high-scale
      operator = {
        replicas = var.operator_replicas
        prometheus = {
          enabled = true
        }
      }

      # Prometheus metrics
      prometheus = {
        enabled = true
      }

      # Tolerations to run on all nodes including GPU taints
      tolerations = [
        {
          operator = "Exists"
        }
      ]
    })
  ]
}

# BGP Peering Policy for TGW Connect
resource "kubernetes_manifest" "bgp_peering_policy" {
  count = var.enable_bgp_peering ? 1 : 0

  manifest = {
    apiVersion = "cilium.io/v2alpha1"
    kind       = "CiliumBGPPeeringPolicy"
    metadata = {
      name = "gpu-inference-bgp"
    }
    spec = {
      nodeSelector = {
        matchLabels = {
          "node-role" = "gpu"
        }
      }
      virtualRouters = [
        {
          localASN = var.bgp_local_asn
          neighbors = [
            for peer in var.bgp_peers : {
              peerAddress             = "${peer.address}/32"
              peerASN                 = peer.asn
              connectRetryTimeSeconds = 30
              holdTimeSeconds         = 90
              keepAliveTimeSeconds    = 30
            }
          ]
          exportPodCIDR = true
        }
      ]
    }
  }

  depends_on = [helm_release.cilium]
}
