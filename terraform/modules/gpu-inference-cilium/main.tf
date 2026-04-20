# ---------------------------------------------------------------------------------------------------------------------
# GPU Inference Cilium v1.19 — Native Routing + BGP Control Plane + Advanced eBPF
# ---------------------------------------------------------------------------------------------------------------------
# Deploys Cilium v1.19 in native-routing mode with BGP Control Plane peering
# to AWS Transit Gateway Connect. Pods get IPs from cluster-pool CIDR
# (100.64.0.0/10), not VPC. Each node is a BGP speaker announcing its Pod CIDR
# to TGW, enabling near-physical-network latency for NCCL/distributed training.
#
# Advanced eBPF features (Issue #144):
#   - Socket-level load balancing for zero-NAT east-west traffic
#   - XDP + Direct Server Return for north-south wire-speed LB
#   - Maglev consistent hashing for long-lived gRPC/NCCL connections
#   - Hubble L7 observability for vLLM (no sidecars, no NCCL overhead)
#   - ClusterMesh for cross-cluster service discovery
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
      # Native routing mode -- no VXLAN/Geneve encapsulation
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

      # Load balancer -- Maglev consistent hashing for long-lived connections.
      # O(1) lookup vs iptables O(n). Critical for gRPC/NCCL sessions that must
      # stick to a backend through scaling events.
      loadBalancer = {
        algorithm = "maglev"
        maglev = {
          tableSize = 65537
          hashSeed  = var.maglev_hash_seed
        }
        serviceTopology = true
        mode            = var.enable_dsr ? "dsr" : "snat"
        dsrDispatch     = var.dsr_dispatch
        acceleration    = var.enable_xdp ? "native" : "disabled"
      }

      # XDP pre-filter -- drop invalid packets at NIC before kernel processing
      enableXDPPrefilter = var.enable_xdp

      # XDP-capable interfaces -- AWS ENA presents as eth0 on Bottlerocket
      devices = var.xdp_devices

      # BPF settings
      bpf = {
        masquerade   = true
        lbMapMax     = tonumber(var.bpf_lb_map_max)
        policyMapMax = tonumber(var.bpf_policy_map_max)
        tproxy       = true
      }

      # No conntrack iptables rules -- eBPF handles it
      installNoConntrackIptablesRules = true

      # Socket-level load balancing for east-west traffic.
      # connect() syscall rewrites directly to backend IP -- zero per-packet NAT.
      sockops = {
        enabled = var.enable_sockops
      }

      # Host-reachable services via socket LB
      hostServices = {
        enabled   = var.enable_sockops
        protocols = "tcp,udp"
      }

      # EDT-based bandwidth management with BBR congestion control.
      # Prevents NCCL all-reduce from starving vLLM inference bandwidth.
      bandwidthManager = {
        enabled = true
        bbr     = true
      }

      # BGP Control Plane
      bgpControlPlane = {
        enabled = true
      }

      # EndpointSlice for 5000-node scale
      endpointSlice = {
        enabled = true
      }

      # Hubble observability -- selective L7 without affecting NCCL/training traffic.
      # HTTP metrics for vLLM API are captured via eBPF kernel hook (no sidecars).
      # Training pods see only DNS-level visibility.
      hubble = {
        enabled = true
        relay = {
          enabled  = true
          replicas = var.hubble_relay_replicas
          resources = {
            requests = { cpu = "100m", memory = "128Mi" }
            limits   = { cpu = "500m", memory = "256Mi" }
          }
        }
        ui = {
          enabled = var.enable_hubble_ui
        }
        metrics = {
          enabled = [
            "dns:query;ignoreAAAA",
            "drop",
            "tcp",
            "flow",
            "port-distribution",
            "httpV2:exemplars=true;labelsContext=source_namespace,source_workload,destination_namespace,destination_workload,traffic_direction",
          ]
          serviceMonitor = {
            enabled = true
          }
          port = 9965
        }
        peerService = {
          clusterDomain = "cluster.local"
        }
      }

      # ClusterMesh -- multi-cluster service discovery for gpu-inference.
      # Enables cross-cluster comms with platform cluster (ArgoCD, VictoriaMetrics,
      # External Secrets) without LoadBalancers or manual DNS.
      cluster = var.enable_clustermesh ? {
        name = var.cluster_mesh_name
        id   = var.cluster_mesh_id
      } : null

      clustermesh = var.enable_clustermesh ? {
        useAPIServer = true
        apiserver = {
          replicas = var.clustermesh_apiserver_replicas
          resources = {
            requests = { cpu = "100m", memory = "256Mi" }
            limits   = { cpu = "500m", memory = "512Mi" }
          }
          service = {
            type = "LoadBalancer"
            annotations = {
              "service.beta.kubernetes.io/aws-load-balancer-internal"        = "true"
              "service.beta.kubernetes.io/aws-load-balancer-type"            = "nlb"
              "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type" = "ip"
            }
          }
          tls = {
            auto = {
              enabled = true
              method  = "helm"
            }
          }
          etcd = {
            resources = {
              requests = { cpu = "100m", memory = "256Mi" }
              limits   = { cpu = "500m", memory = "512Mi" }
            }
          }
        }
      } : null

      # Operator tuning for high-scale
      operator = {
        replicas = var.operator_replicas
        prometheus = {
          enabled = true
        }
        resources = {
          requests = { cpu = "100m", memory = "128Mi" }
          limits   = { cpu = "1000m", memory = "512Mi" }
        }
      }

      # Prometheus metrics
      prometheus = {
        enabled = true
        serviceMonitor = {
          enabled = true
        }
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

# ClusterMesh global service for VictoriaMetrics vminsert.
# gpu-inference pods push metrics directly via ClusterMesh without an NLB.
resource "kubernetes_manifest" "clustermesh_victoriametrics_service" {
  count = var.enable_clustermesh && var.enable_clustermesh_global_services ? 1 : 0

  manifest = {
    apiVersion = "v1"
    kind       = "Service"
    metadata = {
      name      = "victoriametrics-vminsert"
      namespace = "monitoring"
      annotations = {
        "service.cilium.io/global" = "true"
        "service.cilium.io/shared" = "true"
      }
    }
    spec = {
      type  = "ClusterIP"
      ports = [{ port = 8480, targetPort = 8480, protocol = "TCP" }]
      selector = {
        app = "vminsert"
      }
    }
  }

  depends_on = [helm_release.cilium]
}
