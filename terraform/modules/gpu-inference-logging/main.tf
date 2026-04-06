# ---------------------------------------------------------------------------------------------------------------------
# GPU Inference Logging Pipeline — Vector v0.54 + ClickHouse v26.3
# ---------------------------------------------------------------------------------------------------------------------
# Deploys a high-throughput logging pipeline for the gpu-inference cluster:
#   - Vector DaemonSet (Agent role): scrapes kubernetes_logs + journald,
#     parses and filters GPU-relevant log lines, ships to ClickHouse HTTP sink.
#   - ClickHouse StatefulSet: 3-replica cluster on gp3 storage with TTL-based
#     retention. Receives logs via HTTP interface on port 8123.
#   - ConfigMap drives Vector pipeline config; injected as a volume.
# ---------------------------------------------------------------------------------------------------------------------

locals {
  namespace = var.vector_namespace # vector and clickhouse share the logging namespace

  vector_pipeline_config = yamlencode({
    data_dir = "/vector-data-dir"

    sources = {
      kubernetes_logs = {
        type = "kubernetes_logs"
      }

      journald = {
        type = "journald"
      }
    }

    transforms = {
      parse_logs = {
        type   = "remap"
        inputs = ["kubernetes_logs", "journald"]
        source = <<-VRL
          # Promote structured JSON payloads if present
          parsed, err = parse_json(.message)
          if err == null {
            . = merge(., parsed)
          }

          # Normalise timestamp to RFC 3339
          .timestamp = format_timestamp!(now(), "%+")

          # Tag with cluster identity
          .cluster = "gpu-inference"
        VRL
      }

      filter_gpu_logs = {
        type   = "filter"
        inputs = ["parse_logs"]
        # Keep GPU driver, NCCL, DCGM, vLLM, and any CUDA-related messages
        condition = {
          type   = "vrl"
          source = <<-VRL
            contains(string(.message) ?? "", "NCCL") ||
            contains(string(.message) ?? "", "DCGM") ||
            contains(string(.message) ?? "", "vllm") ||
            contains(string(.message) ?? "", "cuda") ||
            contains(string(.kubernetes.pod_labels."app.kubernetes.io/name") ?? "", "vllm") ||
            contains(string(.kubernetes.container_name) ?? "", "gpu")
          VRL
        }
      }
    }

    sinks = {
      clickhouse = {
        type   = "clickhouse"
        inputs = ["filter_gpu_logs"]

        endpoint = "http://clickhouse.${local.namespace}.svc.cluster.local:8123"
        database = "gpu_logs"
        table    = "events"

        auth = {
          strategy = "basic"
          user     = "default"
          password = "{{ CLICKHOUSE_PASSWORD }}"
        }

        batch = {
          max_bytes    = 10485760 # 10 MiB
          timeout_secs = 5
        }

        buffer = {
          type      = "disk"
          max_size  = 268435456 # 256 MiB
          when_full = "block"
        }

        encoding = {
          timestamp_format = "rfc3339"
        }

        healthcheck = {
          enabled = true
        }
      }
    }
  })
}

# ------------------------------------------------------------------
# Namespace
# ------------------------------------------------------------------
resource "kubernetes_namespace" "logging" {
  metadata {
    name   = local.namespace
    labels = merge(var.tags, { "managed-by" = "terragrunt" })
  }
}

# ------------------------------------------------------------------
# Vector ConfigMap
# ------------------------------------------------------------------
resource "kubernetes_config_map" "vector_pipeline" {
  metadata {
    name      = "vector-pipeline-config"
    namespace = kubernetes_namespace.logging.metadata[0].name
    labels    = merge(var.tags, { "app.kubernetes.io/name" = "vector" })
  }

  data = {
    "vector.yaml" = local.vector_pipeline_config
  }
}

# ------------------------------------------------------------------
# ClickHouse Secret
# ------------------------------------------------------------------
resource "kubernetes_secret" "clickhouse_password" {
  metadata {
    name      = "clickhouse-credentials"
    namespace = kubernetes_namespace.logging.metadata[0].name
    labels    = merge(var.tags, { "app.kubernetes.io/name" = "clickhouse" })
  }

  type = "Opaque"

  data = {
    password = var.clickhouse_password
  }
}

# ------------------------------------------------------------------
# ClickHouse StatefulSet — v26.3, 3 replicas, gp3 storage
# ------------------------------------------------------------------
resource "helm_release" "clickhouse" {
  name             = "clickhouse"
  repository       = "https://charts.clickhouse.com"
  chart            = "clickhouse"
  version          = var.clickhouse_version
  namespace        = kubernetes_namespace.logging.metadata[0].name
  create_namespace = false

  wait          = true
  wait_for_jobs = true
  timeout       = 600

  values = [
    yamlencode({
      replicaCount = var.clickhouse_replicas

      image = {
        tag = var.clickhouse_version
      }

      auth = {
        username                  = "default"
        existingSecret            = kubernetes_secret.clickhouse_password.metadata[0].name
        existingSecretPasswordKey = "password"
      }

      persistence = {
        enabled      = true
        size         = var.storage_size
        storageClass = "gp3"
      }

      resources = {
        requests = {
          cpu    = "2"
          memory = "8Gi"
        }
        limits = {
          cpu    = "8"
          memory = "32Gi"
        }
      }

      # ClickHouse configuration overrides
      configuration = {
        users = {
          default = {
            access_management = 1
          }
        }

        profiles = {
          default = {
            max_memory_usage                = "30000000000"
            use_uncompressed_cache          = 0
            load_balancing                  = "random"
            max_partitions_per_insert_block = 100
          }
        }
      }

      # Init container creates the gpu_logs database and events table with TTL
      initContainers = [
        {
          name    = "init-schema"
          image   = "clickhouse/clickhouse-server:${var.clickhouse_version}"
          command = ["/bin/sh", "-c"]
          args = [
            <<-SCRIPT
              until clickhouse-client --host=localhost --user=default --password="$$CLICKHOUSE_PASSWORD" --query="SELECT 1" 2>/dev/null; do
                echo "Waiting for ClickHouse..."
                sleep 3
              done
              clickhouse-client --host=localhost --user=default --password="$$CLICKHOUSE_PASSWORD" \
                --query="CREATE DATABASE IF NOT EXISTS gpu_logs"
              clickhouse-client --host=localhost --user=default --password="$$CLICKHOUSE_PASSWORD" \
                --query="
                  CREATE TABLE IF NOT EXISTS gpu_logs.events (
                    timestamp   DateTime64(3, 'UTC'),
                    cluster     LowCardinality(String),
                    namespace   LowCardinality(String),
                    pod         String,
                    container   String,
                    message     String,
                    labels      Map(String, String),
                    INDEX idx_message message TYPE tokenbf_v1(32768, 3, 0) GRANULARITY 1
                  )
                  ENGINE = MergeTree()
                  PARTITION BY toYYYYMM(timestamp)
                  ORDER BY (cluster, namespace, timestamp)
                  TTL timestamp + INTERVAL ${var.retention_days} DAY
                  SETTINGS index_granularity = 8192
                "
            SCRIPT
          ]
          env = [
            {
              name = "CLICKHOUSE_PASSWORD"
              valueFrom = {
                secretKeyRef = {
                  name = kubernetes_secret.clickhouse_password.metadata[0].name
                  key  = "password"
                }
              }
            }
          ]
        }
      ]

      podLabels = merge(var.tags, { "app.kubernetes.io/name" = "clickhouse" })

      tolerations = [
        {
          operator = "Exists"
        }
      ]
    })
  ]

  depends_on = [kubernetes_namespace.logging]
}

# ------------------------------------------------------------------
# Vector DaemonSet — v0.54, Agent role
# ------------------------------------------------------------------
resource "helm_release" "vector" {
  name             = "vector"
  repository       = "https://helm.vector.dev"
  chart            = "vector"
  version          = var.vector_version
  namespace        = kubernetes_namespace.logging.metadata[0].name
  create_namespace = false

  wait          = true
  wait_for_jobs = true
  timeout       = 300

  values = [
    yamlencode({
      role = "Agent"

      image = {
        tag = var.vector_version
      }

      # Mount our ConfigMap as the pipeline config
      existingConfigMaps = ["vector-pipeline-config"]

      env = [
        {
          name = "CLICKHOUSE_PASSWORD"
          valueFrom = {
            secretKeyRef = {
              name = kubernetes_secret.clickhouse_password.metadata[0].name
              key  = "password"
            }
          }
        }
      ]

      resources = {
        requests = {
          cpu    = "100m"
          memory = "256Mi"
        }
        limits = {
          cpu    = "500m"
          memory = "512Mi"
        }
      }

      # DaemonSet needs host access to read journald and container logs
      hostNetwork = false
      tolerations = [
        {
          operator = "Exists"
        }
      ]

      podLabels = merge(var.tags, { "app.kubernetes.io/name" = "vector" })

      # RBAC for kubernetes_logs source
      rbac = {
        create = true
      }

      serviceAccount = {
        create = true
        name   = "vector"
      }
    })
  ]

  depends_on = [helm_release.clickhouse, kubernetes_config_map.vector_pipeline]
}
