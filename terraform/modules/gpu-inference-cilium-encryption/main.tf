# ---------------------------------------------------------------------------------------------------------------------
# Cilium WireGuard Encryption + High-Scale Tuning
# ---------------------------------------------------------------------------------------------------------------------
# Enables WireGuard transparent encryption on Cilium for gpu-inference cluster
# and applies high-scale tuning for 5000-node operation.
#
# Deployed as a separate ConfigMap + patch to the existing Cilium installation
# (from gpu-inference-cilium module, Issue #70).
# ---------------------------------------------------------------------------------------------------------------------

# ConfigMap with Cilium encryption configuration
resource "kubernetes_config_map_v1" "cilium_encryption_config" {
  metadata {
    name      = "cilium-encryption-config"
    namespace = "kube-system"
    labels = {
      "app.kubernetes.io/name"      = "cilium-encryption"
      "app.kubernetes.io/component" = "config"
    }
  }

  data = {
    "encryption-config.yaml" = yamlencode({
      encryption = {
        enabled = true
        type    = "wireguard"
        wireguard = {
          userspaceFallback = false
        }
      }
    })

    "high-scale-config.yaml" = yamlencode({
      operator = {
        replicas  = var.operator_replicas
        extraArgs = ["--k8s-api-qps=${var.k8s_api_qps}", "--k8s-api-burst=${var.k8s_api_burst}"]
      }
      identityAllocationMode = "crd"
      agent = {
        resources = {
          limits = {
            cpu    = var.agent_cpu_limit
            memory = var.agent_memory_limit
          }
          requests = {
            cpu    = var.agent_cpu_request
            memory = var.agent_memory_request
          }
        }
      }
    })
  }
}

# CiliumNetworkPolicy to optionally exclude NCCL traffic from encryption
resource "kubernetes_manifest" "nccl_no_encrypt_policy" {
  count = var.exclude_nccl_from_encryption ? 1 : 0

  manifest = {
    apiVersion = "cilium.io/v2"
    kind       = "CiliumNetworkPolicy"
    metadata = {
      name      = "gpu-nccl-no-encrypt"
      namespace = "gpu-inference"
    }
    spec = {
      endpointSelector = {
        matchLabels = {
          "app.kubernetes.io/component" = "gpu-worker"
        }
      }
      egress = [
        {
          toEndpoints = [
            {
              matchLabels = {
                "app.kubernetes.io/component" = "gpu-worker"
              }
            }
          ]
          toPorts = [
            {
              ports = [
                for port in var.nccl_port_range : {
                  port     = tostring(port)
                  protocol = "TCP"
                }
              ]
            }
          ]
        }
      ]
    }
  }
}

# PrometheusRule for Cilium monitoring alerts
resource "kubernetes_manifest" "cilium_alerts" {
  count = var.enable_prometheus_alerts ? 1 : 0

  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "PrometheusRule"
    metadata = {
      name      = "cilium-gpu-inference-alerts"
      namespace = "kube-system"
      labels = {
        "prometheus" = "kube-prometheus"
      }
    }
    spec = {
      groups = [
        {
          name = "cilium-gpu-inference"
          rules = [
            {
              alert = "CiliumBGPSessionDown"
              expr  = "cilium_bgp_session_status != 1"
              for   = "5m"
              labels = {
                severity = "critical"
              }
              annotations = {
                summary     = "Cilium BGP session is down on {{ $labels.node }}"
                description = "BGP peering with TGW Connect has been down for more than 5 minutes. Pod routing may be affected."
              }
            },
            {
              alert = "CiliumWireGuardErrors"
              expr  = "rate(cilium_wireguard_error_total[5m]) > 0"
              for   = "10m"
              labels = {
                severity = "warning"
              }
              annotations = {
                summary     = "Cilium WireGuard errors on {{ $labels.node }}"
                description = "WireGuard encryption errors detected. Check kernel module and key rotation."
              }
            },
            {
              alert = "CiliumEndpointCountHigh"
              expr  = "cilium_endpoint_count > 50000"
              for   = "15m"
              labels = {
                severity = "warning"
              }
              annotations = {
                summary     = "High endpoint count on {{ $labels.node }}"
                description = "Cilium endpoint count exceeds 50k. Consider scaling operator or increasing BPF map sizes."
              }
            }
          ]
        }
      ]
    }
  }
}
