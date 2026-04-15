# ---------------------------------------------------------------------------------------------------------------------
# GPU Inference Cilium Advanced eBPF — Monitoring + Identity Policies (Issue #144)
# ---------------------------------------------------------------------------------------------------------------------
# Companion module to gpu-inference-cilium. Manages:
#   1. PrometheusRules for XDP, socket LB, Hubble L7, and ClusterMesh health
#   2. CiliumNetworkPolicy manifests for identity-based zero-trust policies
#   3. Per-pod bandwidth annotations ConfigMap for EDT fair queuing
#   4. Hubble ServiceMonitor for Prometheus scrape
# ---------------------------------------------------------------------------------------------------------------------

# PrometheusRule for all advanced eBPF feature alerts
resource "kubernetes_manifest" "cilium_advanced_alerts" {
  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "PrometheusRule"
    metadata = {
      name      = "cilium-advanced-ebpf-alerts"
      namespace = "kube-system"
      labels = {
        "prometheus"                      = "kube-prometheus"
        "app.kubernetes.io/part-of"       = "cilium-advanced-ebpf"
        "app.kubernetes.io/managed-by"    = "terragrunt"
      }
    }
    spec = {
      groups = [
        # ---- XDP + DSR ----
        {
          name = "cilium.xdp-dsr"
          rules = [
            {
              alert = "CiliumXDPDropRateHigh"
              expr  = "rate(cilium_drop_count_total{reason='XDP dropped'}[5m]) > 1000"
              for   = "5m"
              labels = {
                severity = "warning"
                feature  = "xdp"
              }
              annotations = {
                summary     = "High XDP drop rate on {{ $labels.node }}"
                description = "XDP is dropping {{ $value | humanize }} packets/s. Possible causes: invalid DSR packets, NIC driver mismatch, or XDP program bug. Check: cilium bpf lb list."
              }
            },
            {
              alert = "CiliumDSRServiceMissing"
              expr  = "cilium_services_events_total{action='delete'} > 0 and on(service) cilium_bpf_map_ops_total{map_name='cilium_lb4_services_v2', operation='delete'} > 0"
              for   = "2m"
              labels = {
                severity = "warning"
                feature  = "dsr"
              }
              annotations = {
                summary     = "DSR service entry deleted on {{ $labels.node }}"
                description = "A service with DSR enabled lost its BPF map entry. Clients may experience return-path failures until Cilium reconciles."
              }
            },
          ]
        },
        # ---- Socket-level LB ----
        {
          name = "cilium.socket-lb"
          rules = [
            {
              alert = "CiliumSockopsDisabled"
              # sockops enabled state is surfaced via cilium_feature_status metric (1.18+)
              expr  = "cilium_feature_status{name='sockops'} == 0"
              for   = "5m"
              labels = {
                severity = "warning"
                feature  = "sockops"
              }
              annotations = {
                summary     = "Socket-level LB (sockops) is disabled on {{ $labels.node }}"
                description = "sockops was expected to be enabled. East-west traffic will fall back to per-packet DNAT. Check kernel BPF sockmap support."
              }
            },
          ]
        },
        # ---- Hubble L7 observability ----
        {
          name = "cilium.hubble-l7"
          rules = [
            {
              alert = "HubbleRelayDown"
              expr  = "up{job='hubble-relay'} == 0"
              for   = "5m"
              labels = {
                severity = "critical"
                feature  = "hubble"
              }
              annotations = {
                summary     = "Hubble Relay is down"
                description = "Hubble Relay has been unreachable for 5 minutes. L7 visibility and flow export are unavailable. vLLM HTTP metrics will not appear in Grafana."
              }
            },
            {
              alert = "HubbleFlowsDroppedHigh"
              expr  = "rate(hubble_flows_processed_total{type='drop'}[5m]) > 500"
              for   = "10m"
              labels = {
                severity = "warning"
                feature  = "hubble"
              }
              annotations = {
                summary     = "High Hubble drop rate on {{ $labels.node }}"
                description = "Hubble is dropping {{ $value | humanize }} flows/s — ring buffer may be too small or Relay is slow. Increase hubble.listenAddress ring buffer size."
              }
            },
            {
              alert = "HubbleL7ErrorRateHigh"
              # HTTP 5xx from vLLM inference endpoint captured via Hubble L7 metrics
              expr  = "rate(hubble_http_responses_total{status=~'5..', destination_workload='vllm-inference'}[5m]) / rate(hubble_http_responses_total{destination_workload='vllm-inference'}[5m]) > 0.05"
              for   = "5m"
              labels = {
                severity = "warning"
                feature  = "hubble-l7"
              }
              annotations = {
                summary     = "vLLM HTTP error rate is {{ $value | humanizePercentage }}"
                description = "More than 5% of vLLM inference requests are returning HTTP 5xx. Check vLLM pod logs and GPU memory pressure."
              }
            },
            {
              alert = "HubbleL7LatencyHigh"
              expr  = "histogram_quantile(0.99, rate(hubble_http_request_duration_seconds_bucket{destination_workload='vllm-inference'}[5m])) > 10"
              for   = "5m"
              labels = {
                severity = "warning"
                feature  = "hubble-l7"
              }
              annotations = {
                summary     = "vLLM P99 inference latency is {{ $value }}s"
                description = "vLLM inference P99 latency exceeds 10s. Check GPU utilization (DCGM), token batch size, and NCCL congestion on the same node."
              }
            },
          ]
        },
        # ---- ClusterMesh ----
        {
          name = "cilium.clustermesh"
          rules = [
            {
              alert = "CiliumClusterMeshClusterDown"
              expr  = "cilium_clustermesh_remote_cluster_status == 0"
              for   = "5m"
              labels = {
                severity = "critical"
                feature  = "clustermesh"
              }
              annotations = {
                summary     = "ClusterMesh lost connectivity to {{ $labels.cluster_id }}"
                description = "Cilium ClusterMesh cannot reach remote cluster {{ $labels.cluster_id }} for 5 minutes. Cross-cluster services (External Secrets, VictoriaMetrics, AI SRE) are unreachable from gpu-inference pods."
              }
            },
            {
              alert = "CiliumClusterMeshApiServerDown"
              expr  = "up{job='clustermesh-apiserver'} == 0"
              for   = "5m"
              labels = {
                severity = "critical"
                feature  = "clustermesh"
              }
              annotations = {
                summary     = "ClusterMesh API server is down"
                description = "The ClusterMesh API server (etcd-backed endpoint exchange) has been unreachable for 5 minutes. No new clusters can join and existing connections will degrade."
              }
            },
            {
              alert = "CiliumClusterMeshGlobalServiceEndpointsLow"
              expr  = "cilium_clustermesh_global_services < 2"
              for   = "10m"
              labels = {
                severity = "warning"
                feature  = "clustermesh"
              }
              annotations = {
                summary     = "Fewer than expected global services in ClusterMesh"
                description = "Only {{ $value }} global services are registered. Expected at least 2 (VictoriaMetrics vminsert, External Secrets). Some cross-cluster services may be missing annotations."
              }
            },
          ]
        },
        # ---- Bandwidth Manager (EDT) ----
        {
          name = "cilium.bandwidth-manager"
          rules = [
            {
              alert = "CiliumBandwidthManagerDisabled"
              expr  = "cilium_feature_status{name='bandwidth-manager'} == 0"
              for   = "5m"
              labels = {
                severity = "warning"
                feature  = "bandwidth-manager"
              }
              annotations = {
                summary     = "Bandwidth Manager (EDT) is disabled on {{ $labels.node }}"
                description = "EDT-based fair queuing is off. NCCL all-reduce bursts may starve vLLM inference bandwidth. Check kernel BPF qdisc support (requires kernel 5.1+)."
              }
            },
          ]
        },
      ]
    }
  }
}

# Hubble ServiceMonitor for Prometheus scrape
resource "kubernetes_manifest" "hubble_service_monitor" {
  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "ServiceMonitor"
    metadata = {
      name      = "hubble-metrics"
      namespace = "kube-system"
      labels = {
        "release"                         = "kube-prometheus-stack"
        "app.kubernetes.io/part-of"       = "cilium-advanced-ebpf"
        "app.kubernetes.io/managed-by"    = "terragrunt"
      }
    }
    spec = {
      selector = {
        matchLabels = {
          "k8s-app" = "cilium"
        }
      }
      namespaceSelector = {
        matchNames = ["kube-system"]
      }
      endpoints = [
        {
          # Hubble metrics port (9965) — separate from cilium-agent metrics (9962)
          port     = "hubble-metrics"
          interval = "15s"
          path     = "/metrics"
          relabelings = [
            {
              sourceLabels = ["__meta_kubernetes_pod_node_name"]
              targetLabel  = "node"
              action       = "replace"
            }
          ]
        }
      ]
    }
  }
}

# ConfigMap documenting bandwidth annotations for workload teams
# Per-pod bandwidth limits via EDT (Earliest Departure Time) queuing.
# Prevents NCCL all-reduce from starving vLLM inference on shared NIC.
resource "kubernetes_config_map_v1" "bandwidth_policy_reference" {
  metadata {
    name      = "cilium-bandwidth-policy-reference"
    namespace = "gpu-inference"
    labels = {
      "app.kubernetes.io/part-of"    = "cilium-advanced-ebpf"
      "app.kubernetes.io/managed-by" = "terragrunt"
    }
    annotations = {
      "description" = "Reference ConfigMap documenting per-workload bandwidth annotation values for Cilium EDT queuing"
    }
  }

  data = {
    "bandwidth-annotations.yaml" = yamlencode({
      description = "Add these annotations to pod specs to enable per-pod bandwidth management via Cilium EDT"
      workloads = {
        nccl-training = {
          annotations = {
            "kubernetes.io/ingress-bandwidth" = "80G"
            "kubernetes.io/egress-bandwidth"  = "80G"
          }
          rationale = "NCCL all-reduce needs high bandwidth but must be capped to leave headroom for inference. EFA/RDMA traffic is separate and not affected by EDT."
        }
        vllm-inference = {
          annotations = {
            "kubernetes.io/ingress-bandwidth" = "10G"
            "kubernetes.io/egress-bandwidth"  = "10G"
          }
          rationale = "vLLM token throughput is ~1-5 Gbps per replica. 10G cap ensures stable P99 latency even during NCCL all-reduce bursts on the same node."
        }
        dcgm-exporter = {
          annotations = {
            "kubernetes.io/ingress-bandwidth" = "100M"
            "kubernetes.io/egress-bandwidth"  = "100M"
          }
          rationale = "Metrics export is low-volume. Strict cap prevents runaway scrape from competing with GPU traffic."
        }
      }
    })
  }
}
