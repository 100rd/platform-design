# ---------------------------------------------------------------------------------------------------------------------
# GPU Inference HPA — Custom Autoscaling for vLLM via Prometheus Adapter + VictoriaMetrics
# ---------------------------------------------------------------------------------------------------------------------
# Deploys:
#   1. Prometheus Adapter (prometheus-community/prometheus-adapter) pointed at VictoriaMetrics vmselect.
#   2. Custom metric rules exposing vLLM-specific metrics to the Kubernetes custom-metrics API.
#   3. HorizontalPodAutoscaler for the vLLM Deployment scaling on queue depth and GPU cache pressure.
# ---------------------------------------------------------------------------------------------------------------------

# ---------------------------------------------------------------------------------------------------------------------
# PROMETHEUS ADAPTER
# ---------------------------------------------------------------------------------------------------------------------

resource "helm_release" "prometheus_adapter" {
  name             = "prometheus-adapter"
  namespace        = var.adapter_namespace
  create_namespace = true
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "prometheus-adapter"
  version          = var.prometheus_adapter_version

  wait          = true
  wait_for_jobs = true
  timeout       = 300

  values = [
    yamlencode({
      replicaCount = var.adapter_replicas

      prometheus = {
        # Point at VictoriaMetrics vmselect; it exposes a Prometheus-compatible HTTP API.
        url  = var.vmselect_url
        port = 0 # port is embedded in the URL
      }

      # Resource requests/limits — sized for a large (5000-node) cluster metric volume.
      resources = {
        requests = {
          cpu    = "100m"
          memory = "128Mi"
        }
        limits = {
          cpu    = "500m"
          memory = "512Mi"
        }
      }

      # Affinity — prefer non-GPU nodes so we don't waste GPU capacity on the adapter.
      affinity = {
        nodeAffinity = {
          preferredDuringSchedulingIgnoredDuringExecution = [
            {
              weight = 100
              preference = {
                matchExpressions = [
                  {
                    key      = "node.kubernetes.io/instance-type"
                    operator = "NotIn"
                    values   = ["p4d.24xlarge", "p3.16xlarge", "g5.48xlarge", "g6.48xlarge"]
                  }
                ]
              }
            }
          ]
        }
      }

      # Custom metric rules — expose three vLLM metrics to the custom-metrics API.
      rules = {
        custom = [
          # vllm:num_requests_waiting — queue depth per vLLM pod.
          {
            seriesQuery = "vllm:num_requests_waiting{namespace!=\"\",pod!=\"\"}"
            resources = {
              overrides = {
                namespace = { resource = "namespace" }
                pod       = { resource = "pod" }
              }
            }
            name = {
              matches = "vllm:num_requests_waiting"
              as      = "vllm_requests_waiting"
            }
            metricsQuery = "sum(vllm:num_requests_waiting{<<.LabelMatchers>>}) by (<<.GroupBy>>)"
          },

          # vllm:avg_generation_throughput — tokens/s throughput per pod.
          {
            seriesQuery = "vllm:avg_generation_throughput_toks_per_s{namespace!=\"\",pod!=\"\"}"
            resources = {
              overrides = {
                namespace = { resource = "namespace" }
                pod       = { resource = "pod" }
              }
            }
            name = {
              matches = "vllm:avg_generation_throughput_toks_per_s"
              as      = "vllm_avg_generation_throughput"
            }
            metricsQuery = "avg(vllm:avg_generation_throughput_toks_per_s{<<.LabelMatchers>>}) by (<<.GroupBy>>)"
          },

          # vllm:gpu_cache_usage_perc — KV-cache fill percentage per pod (0-100).
          {
            seriesQuery = "vllm:gpu_cache_usage_perc{namespace!=\"\",pod!=\"\"}"
            resources = {
              overrides = {
                namespace = { resource = "namespace" }
                pod       = { resource = "pod" }
              }
            }
            name = {
              matches = "vllm:gpu_cache_usage_perc"
              as      = "vllm_gpu_cache_usage_perc"
            }
            metricsQuery = "avg(vllm:gpu_cache_usage_perc{<<.LabelMatchers>>}) by (<<.GroupBy>>)"
          }
        ]

        # Expose standard resource metrics (CPU/memory) unchanged — required for kubectl top.
        resource = {
          cpu = {
            containerQuery = "sum(rate(container_cpu_usage_seconds_total{<<.LabelMatchers>>,container!=\"\",pod!=\"\"}[3m])) by (<<.GroupBy>>)"
            nodeQuery      = "sum(rate(container_cpu_usage_seconds_total{<<.LabelMatchers>>,id=\"/\"}[3m])) by (<<.GroupBy>>)"
            resources = {
              overrides = {
                node      = { resource = "node" }
                namespace = { resource = "namespace" }
                pod       = { resource = "pod" }
              }
            }
            containerLabel = "container"
          }
          memory = {
            containerQuery = "sum(container_memory_working_set_bytes{<<.LabelMatchers>>,container!=\"\",pod!=\"\"}) by (<<.GroupBy>>)"
            nodeQuery      = "sum(container_memory_working_set_bytes{<<.LabelMatchers>>,id=\"/\"}) by (<<.GroupBy>>)"
            resources = {
              overrides = {
                node      = { resource = "node" }
                namespace = { resource = "namespace" }
                pod       = { resource = "pod" }
              }
            }
            containerLabel = "container"
          }
          window = "3m"
        }
      }
    })
  ]
}

# ---------------------------------------------------------------------------------------------------------------------
# HPA — vLLM Custom Autoscaler
# ---------------------------------------------------------------------------------------------------------------------

resource "kubernetes_horizontal_pod_autoscaler_v2" "vllm" {
  depends_on = [helm_release.prometheus_adapter]

  metadata {
    name      = "vllm-hpa"
    namespace = var.vllm_namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "platform.sh/component"        = "gpu-inference-hpa"
      "platform.sh/cluster"          = var.cluster_name
    }
    annotations = {
      "platform.sh/issue"       = "79"
      "platform.sh/scaler-type" = "prometheus-adapter"
    }
  }

  spec {
    min_replicas = var.min_replicas
    max_replicas = var.max_replicas

    scale_target_ref {
      api_version = "apps/v1"
      kind        = "Deployment"
      name        = var.vllm_deployment_name
    }

    # Primary metric: request queue depth — scale up fast when requests queue up.
    metric {
      type = "Pods"
      pods {
        metric {
          name = "vllm_requests_waiting"
        }
        target {
          type          = "AverageValue"
          average_value = var.queue_depth_target
        }
      }
    }

    # Secondary metric: GPU KV-cache pressure — scale up before OOM evictions occur.
    metric {
      type = "Pods"
      pods {
        metric {
          name = "vllm_gpu_cache_usage_perc"
        }
        target {
          type          = "AverageValue"
          average_value = var.cache_usage_target
        }
      }
    }

    behavior {
      # Scale-up: react quickly to inference spikes.
      scale_up {
        stabilization_window_seconds = 0
        select_policy                = "Max"

        policy {
          type           = "Percent"
          value          = 100
          period_seconds = 30
        }
        policy {
          type           = "Pods"
          value          = 4
          period_seconds = 30
        }
      }

      # Scale-down: wait 5 minutes before removing pods to avoid flapping.
      scale_down {
        stabilization_window_seconds = 300
        select_policy                = "Min"

        policy {
          type           = "Percent"
          value          = 20
          period_seconds = 60
        }
      }
    }
  }
}
