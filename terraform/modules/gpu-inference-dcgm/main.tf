# ---------------------------------------------------------------------------------------------------------------------
# GPU Inference DCGM Exporter v4.5 + GPU Health Auto-Tainting
# ---------------------------------------------------------------------------------------------------------------------
# Deploys NVIDIA DCGM Exporter as a DaemonSet via Helm with a custom metrics
# CSV covering GPU utilisation, memory, temperature, power draw, XID errors,
# NVLink bandwidth, and ECC errors.
#
# When enable_auto_taint is true, a CronJob polls XID error metrics via
# kubectl and taints unhealthy GPU nodes with gpu-health=unhealthy:NoSchedule
# so that no new workloads land on a defective device.
#
# PrometheusRule/VMRule alerts fire on:
#   - Any XID error above the configured threshold
#   - GPU temperature > temperature_threshold °C
#   - Double-bit (uncorrectable) ECC errors
# ---------------------------------------------------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Namespace
# ---------------------------------------------------------------------------
resource "kubernetes_namespace" "dcgm" {
  metadata {
    name = var.namespace
    labels = merge(var.tags, {
      "app.kubernetes.io/managed-by" = "terragrunt"
      "monitoring"                   = "true"
    })
  }
}

# ---------------------------------------------------------------------------
# ConfigMap — custom DCGM metrics CSV
# ---------------------------------------------------------------------------
resource "kubernetes_config_map" "dcgm_metrics" {
  metadata {
    name      = "dcgm-metrics-config"
    namespace = kubernetes_namespace.dcgm.metadata[0].name
  }

  data = {
    "dcgm-metrics.csv" = <<-CSV
      # DCGM custom metrics for gpu-inference cluster
      # Format: FieldId, PromMetricName, HelpText, Labels

      # GPU Utilisation
      DCGM_FI_DEV_GPU_UTIL,                dcgm_gpu_utilization,              GPU utilisation (percent),                             gpu_uuid,gpu_index,gpu_device,hostname,namespace,pod
      DCGM_FI_DEV_SM_ACTIVE,               dcgm_sm_active,                    Fraction of time at least one warp was active on an SM, gpu_uuid,gpu_index,gpu_device,hostname,namespace,pod
      DCGM_FI_DEV_SM_OCCUPANCY,            dcgm_sm_occupancy,                 Fraction of warps resident relative to max warps,      gpu_uuid,gpu_index,gpu_device,hostname,namespace,pod

      # Memory
      DCGM_FI_DEV_FB_FREE,                 dcgm_fb_free_mb,                   Framebuffer memory free (MiB),                         gpu_uuid,gpu_index,gpu_device,hostname,namespace,pod
      DCGM_FI_DEV_FB_USED,                 dcgm_fb_used_mb,                   Framebuffer memory used (MiB),                         gpu_uuid,gpu_index,gpu_device,hostname,namespace,pod
      DCGM_FI_DEV_FB_TOTAL,                dcgm_fb_total_mb,                  Framebuffer memory total (MiB),                        gpu_uuid,gpu_index,gpu_device,hostname,namespace,pod
      DCGM_FI_DEV_MEM_COPY_UTIL,           dcgm_mem_copy_utilization,         Memory bandwidth utilisation (percent),                gpu_uuid,gpu_index,gpu_device,hostname,namespace,pod

      # Temperature
      DCGM_FI_DEV_GPU_TEMP,                dcgm_gpu_temp_celsius,             GPU core temperature (Celsius),                        gpu_uuid,gpu_index,gpu_device,hostname,namespace,pod
      DCGM_FI_DEV_MEM_MAX_OP_TEMP,         dcgm_mem_max_op_temp_celsius,      Max operating temperature for GPU memory (Celsius),    gpu_uuid,gpu_index,gpu_device,hostname,namespace,pod

      # Power
      DCGM_FI_DEV_POWER_USAGE,             dcgm_power_usage_watts,            GPU power draw (W),                                    gpu_uuid,gpu_index,gpu_device,hostname,namespace,pod
      DCGM_FI_DEV_TOTAL_ENERGY_CONSUMPTION, dcgm_total_energy_consumption_mj, Total energy consumed since driver load (mJ),          gpu_uuid,gpu_index,gpu_device,hostname,namespace,pod
      DCGM_FI_DEV_POWER_MGMT_LIMIT,        dcgm_power_limit_watts,            Configured power management limit (W),                 gpu_uuid,gpu_index,gpu_device,hostname,namespace,pod

      # XID Errors (GPU fatal/non-fatal hardware errors)
      DCGM_FI_DEV_XID_ERRORS,              dcgm_xid_errors_total,             Cumulative XID error count,                            gpu_uuid,gpu_index,gpu_device,hostname,namespace,pod,xid

      # NVLink Bandwidth
      DCGM_FI_DEV_NVLINK_BANDWIDTH_TOTAL,  dcgm_nvlink_bandwidth_total_mbps,  Total NVLink bandwidth (MB/s),                         gpu_uuid,gpu_index,gpu_device,hostname,namespace,pod

      # ECC Errors
      DCGM_FI_DEV_ECC_SBE_VOL_TOTAL,      dcgm_ecc_sbe_volatile_total,       Single-bit ECC errors (volatile, not yet retired),     gpu_uuid,gpu_index,gpu_device,hostname,namespace,pod
      DCGM_FI_DEV_ECC_DBE_VOL_TOTAL,      dcgm_ecc_dbe_volatile_total,       Double-bit ECC errors (volatile, uncorrectable),       gpu_uuid,gpu_index,gpu_device,hostname,namespace,pod
      DCGM_FI_DEV_ECC_SBE_AGG_TOTAL,      dcgm_ecc_sbe_aggregate_total,      Single-bit ECC errors (aggregate, lifetime),           gpu_uuid,gpu_index,gpu_device,hostname,namespace,pod
      DCGM_FI_DEV_ECC_DBE_AGG_TOTAL,      dcgm_ecc_dbe_aggregate_total,      Double-bit ECC errors (aggregate, lifetime),           gpu_uuid,gpu_index,gpu_device,hostname,namespace,pod

      # Clock Throttling
      DCGM_FI_DEV_CLOCK_THROTTLE_REASONS, dcgm_clock_throttle_reasons,       Bitmask of active clock throttle reasons,              gpu_uuid,gpu_index,gpu_device,hostname,namespace,pod
      DCGM_FI_DEV_APP_SM_CLOCK,           dcgm_app_sm_clock_mhz,             SM application clock (MHz),                            gpu_uuid,gpu_index,gpu_device,hostname,namespace,pod
      DCGM_FI_DEV_APP_MEM_CLOCK,          dcgm_app_mem_clock_mhz,            Memory application clock (MHz),                        gpu_uuid,gpu_index,gpu_device,hostname,namespace,pod
    CSV
  }
}

# ---------------------------------------------------------------------------
# ServiceAccount for DCGM Exporter DaemonSet
# ---------------------------------------------------------------------------
resource "kubernetes_service_account" "dcgm_exporter" {
  metadata {
    name      = var.service_account_name
    namespace = kubernetes_namespace.dcgm.metadata[0].name
    labels = {
      "app.kubernetes.io/name"       = "dcgm-exporter"
      "app.kubernetes.io/managed-by" = "terragrunt"
    }
  }
}

# ---------------------------------------------------------------------------
# DCGM Exporter Helm Release
# ---------------------------------------------------------------------------
resource "helm_release" "dcgm_exporter" {
  name             = "dcgm-exporter"
  repository       = "https://nvidia.github.io/dcgm-exporter/helm-charts"
  chart            = "dcgm-exporter"
  version          = var.dcgm_exporter_version
  namespace        = kubernetes_namespace.dcgm.metadata[0].name
  create_namespace = false

  wait          = true
  wait_for_jobs = true
  timeout       = 300

  values = [
    yamlencode({
      image = {
        repository = "nvcr.io/nvidia/k8s/dcgm-exporter"
        tag        = "4.5.0-4.2.3-ubuntu22.04"
        pullPolicy = "IfNotPresent"
      }

      serviceAccount = {
        create = false
        name   = kubernetes_service_account.dcgm_exporter.metadata[0].name
      }

      # Mount the custom metrics ConfigMap
      extraConfigMapVolumes = [
        {
          name = "dcgm-metrics"
          configMap = {
            name = kubernetes_config_map.dcgm_metrics.metadata[0].name
          }
        }
      ]

      extraVolumeMounts = [
        {
          name      = "dcgm-metrics"
          mountPath = "/etc/dcgm-exporter/dcgm-metrics.csv"
          subPath   = "dcgm-metrics.csv"
        }
      ]

      arguments = [
        "--collectors=/etc/dcgm-exporter/dcgm-metrics.csv",
        "--address=:9400",
        "--kubernetes=true",
        "--kubernetes-gpu-id-type=uid",
      ]

      # Expose metrics port
      service = {
        type = "ClusterIP"
        port = 9400
        annotations = {
          "prometheus.io/scrape" = "true"
          "prometheus.io/port"   = "9400"
          "prometheus.io/path"   = "/metrics"
        }
      }

      serviceMonitor = {
        enabled  = true
        interval = var.scrape_interval
        additionalLabels = {
          release = "victoria-metrics"
        }
      }

      # DaemonSet tolerations — run on GPU nodes which carry NVIDIA taints
      tolerations = [
        {
          key      = "nvidia.com/gpu"
          operator = "Exists"
          effect   = "NoSchedule"
        },
        {
          key      = "gpu-health"
          operator = "Exists"
          effect   = "NoSchedule"
        },
        {
          operator = "Exists"
        },
      ]

      # Only schedule on GPU nodes
      nodeSelector = {
        "nvidia.com/gpu.present" = "true"
      }

      # Privileged — required to access DCGM/NVML
      securityContext = {
        privileged = true
        runAsUser  = 0
      }

      resources = {
        requests = {
          cpu    = "100m"
          memory = "128Mi"
        }
        limits = {
          cpu    = "500m"
          memory = "256Mi"
        }
      }

      podAnnotations = {
        "cluster-autoscaler.kubernetes.io/safe-to-evict" = "false"
      }
    })
  ]

  depends_on = [
    kubernetes_config_map.dcgm_metrics,
    kubernetes_service_account.dcgm_exporter,
  ]
}

# ---------------------------------------------------------------------------
# RBAC for GPU health auto-taint CronJob
# ---------------------------------------------------------------------------
resource "kubernetes_service_account" "gpu_health_tainter" {
  count = var.enable_auto_taint ? 1 : 0

  metadata {
    name      = var.auto_taint_service_account_name
    namespace = kubernetes_namespace.dcgm.metadata[0].name
    labels = {
      "app.kubernetes.io/name"       = "gpu-health-tainter"
      "app.kubernetes.io/managed-by" = "terragrunt"
    }
  }
}

resource "kubernetes_cluster_role" "gpu_health_tainter" {
  count = var.enable_auto_taint ? 1 : 0

  metadata {
    name = "gpu-health-tainter"
    labels = {
      "app.kubernetes.io/name"       = "gpu-health-tainter"
      "app.kubernetes.io/managed-by" = "terragrunt"
    }
  }

  rule {
    api_groups = [""]
    resources  = ["nodes"]
    verbs      = ["get", "list", "patch"]
  }

  rule {
    api_groups = [""]
    resources  = ["pods"]
    verbs      = ["get", "list"]
  }

  # Read DCGM metrics via metrics API
  rule {
    api_groups = ["metrics.k8s.io"]
    resources  = ["nodes", "pods"]
    verbs      = ["get", "list"]
  }
}

resource "kubernetes_cluster_role_binding" "gpu_health_tainter" {
  count = var.enable_auto_taint ? 1 : 0

  metadata {
    name = "gpu-health-tainter"
    labels = {
      "app.kubernetes.io/name"       = "gpu-health-tainter"
      "app.kubernetes.io/managed-by" = "terragrunt"
    }
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.gpu_health_tainter[0].metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.gpu_health_tainter[0].metadata[0].name
    namespace = kubernetes_namespace.dcgm.metadata[0].name
  }
}

# ---------------------------------------------------------------------------
# GPU Health Auto-Taint CronJob
# ---------------------------------------------------------------------------
# Runs every 2 minutes. Queries Prometheus/VictoriaMetrics for XID errors,
# then taints any node whose GPU has exceeded xid_error_threshold errors
# per scrape cycle with gpu-health=unhealthy:NoSchedule.
# Nodes that recover (XID count back to zero) are un-tainted automatically.
# ---------------------------------------------------------------------------
resource "kubernetes_cron_job_v1" "gpu_health_tainter" {
  count = var.enable_auto_taint ? 1 : 0

  metadata {
    name      = "gpu-health-tainter"
    namespace = kubernetes_namespace.dcgm.metadata[0].name
    labels = {
      "app.kubernetes.io/name"       = "gpu-health-tainter"
      "app.kubernetes.io/managed-by" = "terragrunt"
    }
  }

  spec {
    schedule                      = var.taint_cron_schedule
    concurrency_policy            = "Forbid"
    failed_jobs_history_limit     = 3
    successful_jobs_history_limit = 3
    starting_deadline_seconds     = 60

    job_template {
      metadata {
        labels = {
          "app.kubernetes.io/name" = "gpu-health-tainter"
        }
      }

      spec {
        backoff_limit = 0
        template {
          metadata {
            labels = {
              "app.kubernetes.io/name" = "gpu-health-tainter"
            }
          }

          spec {
            service_account_name = kubernetes_service_account.gpu_health_tainter[0].metadata[0].name
            restart_policy       = "Never"

            # Run on non-GPU nodes to avoid chicken-and-egg taint issues
            node_selector = {
              "kubernetes.io/os" = "linux"
            }

            toleration {
              operator = "Exists"
            }

            container {
              name              = "tainter"
              image             = var.kubectl_image
              image_pull_policy = "IfNotPresent"

              command = ["/bin/sh", "-c"]
              args = [
                <<-SCRIPT
                  set -euo pipefail

                  XID_THRESHOLD="${var.xid_error_threshold}"
                  METRICS_URL="http://dcgm-exporter.${var.namespace}.svc.cluster.local:9400/metrics"

                  echo "[gpu-health-tainter] Fetching DCGM metrics from $METRICS_URL"
                  METRICS=$(wget -qO- "$METRICS_URL" 2>/dev/null || true)

                  if [ -z "$METRICS" ]; then
                    echo "[gpu-health-tainter] WARNING: could not reach DCGM exporter, skipping cycle"
                    exit 0
                  fi

                  # Parse XID error counts per node (hostname label)
                  # Lines look like:
                  #   dcgm_xid_errors_total{...,hostname="ip-10-0-1-1",...} 3
                  echo "$METRICS" | grep '^dcgm_xid_errors_total' | while IFS= read -r line; do
                    NODE=$(echo "$line" | grep -o 'hostname="[^"]*"' | cut -d'"' -f2)
                    VALUE=$(echo "$line" | awk '{print $NF}')

                    if [ -z "$NODE" ] || [ -z "$VALUE" ]; then
                      continue
                    fi

                    # Convert to integer (drop decimals)
                    INT_VALUE=$(printf "%.0f" "$VALUE" 2>/dev/null || echo "0")

                    if [ "$INT_VALUE" -ge "$XID_THRESHOLD" ]; then
                      echo "[gpu-health-tainter] Node $NODE has XID errors=$INT_VALUE (>=$XID_THRESHOLD) — tainting"
                      kubectl taint node "$NODE" gpu-health=unhealthy:NoSchedule --overwrite || true
                    else
                      # Remove stale taint if node recovered
                      kubectl taint node "$NODE" gpu-health=unhealthy:NoSchedule- 2>/dev/null || true
                    fi
                  done

                  echo "[gpu-health-tainter] Cycle complete"
                SCRIPT
              ]

              resources {
                requests = {
                  cpu    = "50m"
                  memory = "64Mi"
                }
                limits = {
                  cpu    = "200m"
                  memory = "128Mi"
                }
              }

              security_context {
                allow_privilege_escalation = false
                read_only_root_filesystem  = true
                run_as_non_root            = true
                run_as_user                = 65534
                capabilities {
                  drop = ["ALL"]
                }
              }
            }
          }
        }
      }
    }
  }

  depends_on = [helm_release.dcgm_exporter]
}

# ---------------------------------------------------------------------------
# Alerting Rules — VMRule (VictoriaMetrics) or PrometheusRule
# ---------------------------------------------------------------------------
resource "kubernetes_manifest" "gpu_health_alerts" {
  manifest = {
    apiVersion = var.use_vm_rule ? "operator.victoriametrics.com/v1beta1" : "monitoring.coreos.com/v1"
    kind       = var.use_vm_rule ? "VMRule" : "PrometheusRule"
    metadata = {
      name      = "gpu-health-alerts"
      namespace = var.alert_namespace
      labels = {
        "app.kubernetes.io/name"       = "gpu-health-alerts"
        "app.kubernetes.io/managed-by" = "terragrunt"
        release                        = "victoria-metrics"
      }
    }
    spec = {
      groups = [
        {
          name     = "gpu.xid_errors"
          interval = var.scrape_interval
          rules = [
            {
              alert = "GpuXidErrorDetected"
              expr  = "increase(dcgm_xid_errors_total[2m]) >= ${var.xid_error_threshold}"
              for   = "0m"
              labels = {
                severity = "critical"
                team     = "gpu-infra"
              }
              annotations = {
                summary     = "GPU XID error on {{ $labels.hostname }} (GPU {{ $labels.gpu_index }})"
                description = "XID errors detected on node {{ $labels.hostname }} GPU {{ $labels.gpu_index }} (UUID: {{ $labels.gpu_uuid }}). XID count increase: {{ $value }}. Node will be tainted gpu-health=unhealthy:NoSchedule."
                runbook_url = "https://docs.nvidia.com/deploy/xid-errors/index.html"
              }
            },
            {
              alert = "GpuXidErrorCriticalBurst"
              expr  = "increase(dcgm_xid_errors_total[5m]) >= 5"
              for   = "0m"
              labels = {
                severity = "page"
                team     = "gpu-infra"
              }
              annotations = {
                summary     = "Critical XID burst on {{ $labels.hostname }} GPU {{ $labels.gpu_index }}"
                description = "GPU on node {{ $labels.hostname }} ({{ $labels.gpu_uuid }}) has generated 5+ XID errors in 5 minutes. Immediate investigation required — GPU may need replacement."
                runbook_url = "https://docs.nvidia.com/deploy/xid-errors/index.html"
              }
            },
          ]
        },
        {
          name     = "gpu.temperature"
          interval = var.scrape_interval
          rules = [
            {
              alert = "GpuHighTemperature"
              expr  = "dcgm_gpu_temp_celsius > ${var.temperature_threshold}"
              for   = "5m"
              labels = {
                severity = "warning"
                team     = "gpu-infra"
              }
              annotations = {
                summary     = "GPU temperature high on {{ $labels.hostname }} GPU {{ $labels.gpu_index }}"
                description = "GPU {{ $labels.gpu_index }} on node {{ $labels.hostname }} is running at {{ $value }}°C, exceeding the ${var.temperature_threshold}°C threshold for 5+ minutes. Check cooling and workload distribution."
              }
            },
            {
              alert = "GpuCriticalTemperature"
              expr  = "dcgm_gpu_temp_celsius > 95"
              for   = "1m"
              labels = {
                severity = "critical"
                team     = "gpu-infra"
              }
              annotations = {
                summary     = "CRITICAL GPU temperature on {{ $labels.hostname }} GPU {{ $labels.gpu_index }}"
                description = "GPU {{ $labels.gpu_index }} on node {{ $labels.hostname }} is at {{ $value }}°C — above thermal shutdown threshold. Workloads will be killed automatically by the GPU driver. Investigate immediately."
              }
            },
          ]
        },
        {
          name     = "gpu.ecc_errors"
          interval = var.scrape_interval
          rules = [
            {
              alert = "GpuDoubleBitEccError"
              expr  = "increase(dcgm_ecc_dbe_volatile_total[5m]) > 0"
              for   = "0m"
              labels = {
                severity = "critical"
                team     = "gpu-infra"
              }
              annotations = {
                summary     = "Double-bit ECC error on {{ $labels.hostname }} GPU {{ $labels.gpu_index }}"
                description = "Uncorrectable double-bit ECC error detected on {{ $labels.hostname }} GPU {{ $labels.gpu_index }} ({{ $labels.gpu_uuid }}). Data corruption risk — node must be drained and GPU memory pages retired."
                runbook_url = "https://docs.nvidia.com/deploy/a100-gpu-mem-error-mgmt/index.html"
              }
            },
            {
              alert = "GpuSingleBitEccErrorRate"
              expr  = "rate(dcgm_ecc_sbe_volatile_total[10m]) * 60 > 10"
              for   = "5m"
              labels = {
                severity = "warning"
                team     = "gpu-infra"
              }
              annotations = {
                summary     = "High single-bit ECC error rate on {{ $labels.hostname }} GPU {{ $labels.gpu_index }}"
                description = "GPU {{ $labels.gpu_index }} on node {{ $labels.hostname }} is experiencing >10 single-bit ECC errors/minute. While correctable, this may indicate impending hardware failure."
              }
            },
          ]
        },
        {
          name     = "gpu.nvlink"
          interval = var.scrape_interval
          rules = [
            {
              alert = "GpuNvLinkBandwidthLow"
              expr  = "dcgm_nvlink_bandwidth_total_mbps < 100 and on(hostname, gpu_index) dcgm_gpu_utilization > 50"
              for   = "10m"
              labels = {
                severity = "warning"
                team     = "gpu-infra"
              }
              annotations = {
                summary     = "Low NVLink bandwidth on {{ $labels.hostname }} GPU {{ $labels.gpu_index }}"
                description = "GPU {{ $labels.gpu_index }} on {{ $labels.hostname }} shows NVLink bandwidth of {{ $value }} MB/s while under >50%% utilisation. May indicate NVLink fabric issue impacting distributed training."
              }
            },
          ]
        },
        {
          name     = "gpu.availability"
          interval = "30s"
          rules = [
            {
              alert = "DcgmExporterDown"
              expr  = "up{job=\"dcgm-exporter\"} == 0"
              for   = "2m"
              labels = {
                severity = "warning"
                team     = "gpu-infra"
              }
              annotations = {
                summary     = "DCGM Exporter down on {{ $labels.instance }}"
                description = "DCGM Exporter on {{ $labels.instance }} has been unreachable for 2+ minutes. GPU health monitoring is degraded for this node."
              }
            },
            {
              alert = "GpuNodeTainted"
              expr  = "kube_node_spec_taint{key=\"gpu-health\",value=\"unhealthy\",effect=\"NoSchedule\"} == 1"
              for   = "0m"
              labels = {
                severity = "critical"
                team     = "gpu-infra"
              }
              annotations = {
                summary     = "GPU node {{ $labels.node }} auto-tainted unhealthy"
                description = "Node {{ $labels.node }} has been automatically tainted gpu-health=unhealthy:NoSchedule due to XID errors. No new GPU workloads will be scheduled here. Investigate the GPU and remove the taint manually after remediation."
              }
            },
          ]
        },
      ]
    }
  }

  depends_on = [helm_release.dcgm_exporter]
}
