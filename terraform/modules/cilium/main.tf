# ---------------------------------------------------------------------------------------------------------------------
# Cilium CNI Module
# ---------------------------------------------------------------------------------------------------------------------
# Deploys Cilium as the CNI for EKS clusters, replacing AWS VPC CNI.
# Uses ENI IPAM mode for VPC-routable pod IPs (same behavior as VPC CNI).
#
# Prerequisites:
#   - EKS cluster must be created WITHOUT vpc-cni addon
#   - Nodes must use Bottlerocket AMI (has Cilium support built-in)
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
      # EKS-specific settings
      eni = {
        enabled = true
        # Use the same subnets as the cluster
        awsEnablePrefixDelegation = var.enable_prefix_delegation
        updateEC2AdapterLimitViaAPI = true
        # Required for Bottlerocket
        awsReleaseExcessIPs = true
      }

      # IPAM mode: ENI for VPC-routable IPs
      ipam = {
        mode = "eni"
      }

      # Native routing (no overlay/tunneling)
      routingMode = "native"

      # EKS uses aws-node for IPAM initially, Cilium takes over
      cni = {
        chainingMode = "none"
        exclusive    = true
      }

      # Disable default CNI to prevent conflicts
      enableIPv4Masquerade = true
      enableIPv6Masquerade = false

      # kube-proxy replacement (eBPF-based service handling)
      kubeProxyReplacement = var.replace_kube_proxy

      # Required when replacing kube-proxy
      k8sServiceHost = var.cluster_endpoint
      k8sServicePort = 443

      # Hubble observability
      hubble = {
        enabled = var.enable_hubble
        relay = {
          enabled = var.enable_hubble
        }
        ui = {
          enabled = var.enable_hubble_ui
        }
        metrics = {
          enabled = var.enable_hubble ? [
            "dns",
            "drop",
            "tcp",
            "flow",
            "port-distribution",
            "icmp",
            "httpV2:exemplars=true;labelsContext=source_ip,source_namespace,source_workload,destination_ip,destination_namespace,destination_workload,traffic_direction"
          ] : []
          serviceMonitor = {
            enabled = var.enable_service_monitor
          }
        }
      }

      # Operator configuration
      operator = {
        replicas = var.operator_replicas
        resources = {
          requests = {
            cpu    = "100m"
            memory = "128Mi"
          }
          limits = {
            cpu    = "1000m"
            memory = "512Mi"
          }
        }
      }

      # Agent configuration
      resources = {
        requests = {
          cpu    = "100m"
          memory = "256Mi"
        }
        limits = {
          cpu    = "2000m"
          memory = "1Gi"
        }
      }

      # Bottlerocket-specific mount paths
      cgroup = {
        hostRoot = "/sys/fs/cgroup"
      }

      # BPF settings
      bpf = {
        masquerade    = true
        clockProbe    = false
        preallocateMaps = true
        tproxy        = true
      }

      # Enable bandwidth manager for better network QoS
      bandwidthManager = {
        enabled = var.enable_bandwidth_manager
        bbr     = true
      }

      # Load balancer settings
      loadBalancer = {
        algorithm = "maglev"
      }

      # Enable local redirect policy for node-local DNS
      localRedirectPolicy = true

      # Security
      securityContext = {
        capabilities = {
          ciliumAgent = [
            "CHOWN", "KILL", "NET_ADMIN", "NET_RAW", "IPC_LOCK",
            "SYS_ADMIN", "SYS_RESOURCE", "DAC_OVERRIDE", "FOWNER", "SETGID", "SETUID"
          ]
          cleanCiliumState = ["NET_ADMIN", "SYS_ADMIN", "SYS_RESOURCE"]
        }
      }

      # Tolerations to run on all nodes
      tolerations = [
        {
          operator = "Exists"
        }
      ]

      # Node selector for agent
      nodeSelector = {
        "kubernetes.io/os" = "linux"
      }

      # Pod labels
      podLabels = {
        "app.kubernetes.io/part-of" = "cilium"
      }

      # Extra config
      extraConfig = var.extra_config
    })
  ]

  depends_on = [var.module_depends_on]
}

# Cilium ClusterwideNetworkPolicy for default deny (optional)
resource "kubernetes_manifest" "default_deny_policy" {
  count = var.enable_default_deny ? 1 : 0

  manifest = {
    apiVersion = "cilium.io/v2"
    kind       = "CiliumClusterwideNetworkPolicy"
    metadata = {
      name = "default-deny-all"
    }
    spec = {
      description = "Default deny all traffic except explicitly allowed"
      endpointSelector = {}
      ingress = [
        {
          fromEndpoints = [
            {
              matchLabels = {
                "reserved:init" = ""
              }
            }
          ]
        }
      ]
      egress = [
        {
          toEndpoints = [
            {
              matchLabels = {
                "reserved:init" = ""
              }
            }
          ]
        },
        {
          toEntities = ["kube-apiserver", "host"]
        },
        {
          toEndpoints = [
            {
              matchLabels = {
                "k8s:io.kubernetes.pod.namespace" = "kube-system"
                "k8s:k8s-app"                     = "kube-dns"
              }
            }
          ]
          toPorts = [
            {
              ports = [
                { port = "53", protocol = "UDP" },
                { port = "53", protocol = "TCP" }
              ]
            }
          ]
        }
      ]
    }
  }

  depends_on = [helm_release.cilium]
}
