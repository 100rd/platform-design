# ---------------------------------------------------------------------------------------------------------------------
# vLLM v0.19 Deployment — GPU Inference Module
# ---------------------------------------------------------------------------------------------------------------------
# Deploys vLLM v0.19 on the gpu-inference EKS cluster with:
#   - DRA ResourceClaimTemplate for H100 SXM5 GPU allocation (8 GPUs/pod)
#   - Volcano scheduler for gang scheduling
#   - Multi-LoRA adapter support (up to 8 simultaneous adapters)
#   - VictoriaMetrics VMServiceScrape for metrics collection
#   - ClusterIP service on port 8000
# ---------------------------------------------------------------------------------------------------------------------

locals {
  common_labels = merge(
    {
      "app.kubernetes.io/name"       = "vllm"
      "app.kubernetes.io/component"  = "inference-server"
      "app.kubernetes.io/version"    = var.vllm_version
      "app.kubernetes.io/part-of"    = "gpu-inference"
      "app.kubernetes.io/managed-by" = "terraform"
    },
    var.tags
  )

  lora_modules_yaml = join("\n", [
    for m in var.lora_modules : "      - name: ${m.name}\n        path: ${m.path}"
  ])

  model_path = "/models/${var.model_name}"

  served_model_name = replace(
    replace(var.model_name, "/", "-"),
    "_", "-"
  )
}

# ---------------------------------------------------------------------------------------------------------------------
# Namespace
# ---------------------------------------------------------------------------------------------------------------------

resource "kubernetes_manifest" "namespace" {
  manifest = {
    apiVersion = "v1"
    kind       = "Namespace"
    metadata = {
      name = var.namespace
      labels = {
        "app.kubernetes.io/part-of" = "gpu-inference"
        "managed-by"                = "terraform"
      }
    }
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# ServiceAccount
# ---------------------------------------------------------------------------------------------------------------------

resource "kubernetes_manifest" "service_account" {
  depends_on = [kubernetes_manifest.namespace]

  manifest = {
    apiVersion = "v1"
    kind       = "ServiceAccount"
    metadata = {
      name      = "vllm"
      namespace = var.namespace
      labels    = local.common_labels
    }
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# DRA ResourceClaimTemplate — allocates 8 H100 GPUs per pod via DRA
# ---------------------------------------------------------------------------------------------------------------------

resource "kubernetes_manifest" "resource_claim_template" {
  depends_on = [kubernetes_manifest.namespace]

  manifest = {
    apiVersion = "resource.k8s.io/v1beta1"
    kind       = "ResourceClaimTemplate"
    metadata = {
      name      = var.resource_claim_template_name
      namespace = var.namespace
      labels    = local.common_labels
    }
    spec = {
      spec = {
        devices = {
          requests = [
            {
              name            = "gpu"
              deviceClassName = "gpu.nvidia.com"
              count           = var.tensor_parallel_size
            }
          ]
          config = [
            {
              requests = ["gpu"]
              opaque = {
                driver = "gpu.nvidia.com"
                parameters = {
                  apiVersion = "gpu.nvidia.com/v1alpha1"
                  kind       = "GpuClaimParameters"
                  sharing = {
                    strategy = "None"
                  }
                }
              }
            }
          ]
        }
      }
    }
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# ConfigMap — vLLM runtime configuration
# ---------------------------------------------------------------------------------------------------------------------

resource "kubernetes_manifest" "configmap" {
  depends_on = [kubernetes_manifest.namespace]

  manifest = {
    apiVersion = "v1"
    kind       = "ConfigMap"
    metadata = {
      name      = "vllm-config"
      namespace = var.namespace
      labels    = local.common_labels
    }
    data = {
      "model-path"           = local.model_path
      "tensor-parallel-size" = tostring(var.tensor_parallel_size)
      "max-model-len"        = tostring(var.max_model_len)
      "enable-lora"          = tostring(var.enable_lora)
      "max-loras"            = tostring(var.max_loras)
      "vllm-config.yaml" = yamlencode({
        model                  = local.model_path
        tensor-parallel-size   = var.tensor_parallel_size
        max-model-len          = var.max_model_len
        enable-lora            = var.enable_lora
        max-loras              = var.max_loras
        lora-extra-vocab-size  = 256
        max-cpu-loras          = 32
        gpu-memory-utilization = var.gpu_memory_utilization
        dtype                  = "bfloat16"
        disable-log-requests   = false
        uvicorn-log-level      = "warning"
        port                   = 8000
        host                   = "0.0.0.0"
        served-model-name      = local.served_model_name
        lora-modules           = var.lora_modules
      })
    }
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# Deployment — vLLM v0.19 with DRA GPU allocation and Volcano scheduler
# ---------------------------------------------------------------------------------------------------------------------

resource "kubernetes_manifest" "deployment" {
  depends_on = [
    kubernetes_manifest.namespace,
    kubernetes_manifest.service_account,
    kubernetes_manifest.configmap,
    kubernetes_manifest.resource_claim_template,
  ]

  manifest = {
    apiVersion = "apps/v1"
    kind       = "Deployment"
    metadata = {
      name      = "vllm"
      namespace = var.namespace
      labels    = local.common_labels
    }
    spec = {
      replicas = var.replicas
      selector = {
        matchLabels = {
          "app.kubernetes.io/name"      = "vllm"
          "app.kubernetes.io/component" = "inference-server"
        }
      }
      strategy = {
        type = "RollingUpdate"
        rollingUpdate = {
          maxUnavailable = 1
          maxSurge       = 0
        }
      }
      template = {
        metadata = {
          labels = local.common_labels
          annotations = {
            "prometheus.io/scrape" = "true"
            "prometheus.io/port"   = "8000"
            "prometheus.io/path"   = "/metrics"
          }
        }
        spec = {
          schedulerName                 = var.scheduler_name
          priorityClassName             = var.priority_class_name
          serviceAccountName            = "vllm"
          terminationGracePeriodSeconds = 120

          affinity = {
            nodeAffinity = {
              requiredDuringSchedulingIgnoredDuringExecution = {
                nodeSelectorTerms = [
                  {
                    matchExpressions = [
                      {
                        key      = "gpu-inference"
                        operator = "In"
                        values   = ["true"]
                      },
                      {
                        key      = "nvidia.com/gpu.product"
                        operator = "In"
                        values   = ["H100-SXM5"]
                      }
                    ]
                  }
                ]
              }
            }
            podAntiAffinity = {
              preferredDuringSchedulingIgnoredDuringExecution = [
                {
                  weight = 100
                  podAffinityTerm = {
                    labelSelector = {
                      matchLabels = {
                        "app.kubernetes.io/name" = "vllm"
                      }
                    }
                    topologyKey = "kubernetes.io/hostname"
                  }
                }
              ]
            }
          }

          tolerations = [
            {
              key      = "nvidia.com/gpu"
              operator = "Exists"
              effect   = "NoSchedule"
            }
          ]

          resourceClaims = [
            {
              name                      = "gpu-claim"
              resourceClaimTemplateName = var.resource_claim_template_name
            }
          ]

          volumes = [
            {
              name = "vllm-config"
              configMap = {
                name = "vllm-config"
              }
            },
            {
              name     = "model-storage"
              emptyDir = {}
            },
            {
              name     = "lora-adapters"
              emptyDir = {}
            },
            {
              name = "shm"
              emptyDir = {
                medium    = "Memory"
                sizeLimit = "64Gi"
              }
            }
          ]

          initContainers = [
            {
              name    = "model-loader"
              image   = "busybox:1.36"
              command = ["/bin/sh", "-c", "echo 'Model loading placeholder — replace with actual model pull init container'"]
              resources = {
                requests = { cpu = "100m", memory = "128Mi" }
                limits   = { cpu = "500m", memory = "512Mi" }
              }
              volumeMounts = [
                { name = "model-storage", mountPath = "/models" }
              ]
            }
          ]

          containers = [
            {
              name            = "vllm"
              image           = "vllm/vllm-openai:v${var.vllm_version}"
              imagePullPolicy = "IfNotPresent"
              command = [
                "python3", "-m", "vllm.entrypoints.openai.api_server",
                "--config", "/etc/vllm/vllm-config.yaml"
              ]
              ports = [
                { name = "http", containerPort = 8000, protocol = "TCP" }
              ]
              env = [
                { name = "VLLM_WORKER_MULTIPROC_METHOD", value = "spawn" },
                { name = "NCCL_DEBUG", value = "WARN" },
                { name = "NCCL_IB_DISABLE", value = "0" },
                { name = "NCCL_NET_GDR_LEVEL", value = "5" },
                {
                  name = "HUGGING_FACE_HUB_TOKEN"
                  valueFrom = {
                    secretKeyRef = {
                      name     = "vllm-secrets"
                      key      = "hf-token"
                      optional = true
                    }
                  }
                }
              ]
              resources = {
                requests = { cpu = "16", memory = "128Gi" }
                limits   = { cpu = "32", memory = "256Gi" }
                claims   = [{ name = "gpu-claim" }]
              }
              volumeMounts = [
                { name = "vllm-config", mountPath = "/etc/vllm", readOnly = true },
                { name = "model-storage", mountPath = "/models" },
                { name = "lora-adapters", mountPath = "/lora-adapters" },
                { name = "shm", mountPath = "/dev/shm" }
              ]
              livenessProbe = {
                httpGet             = { path = "/health", port = "http" }
                initialDelaySeconds = 120
                periodSeconds       = 30
                failureThreshold    = 5
              }
              readinessProbe = {
                httpGet             = { path = "/health", port = "http" }
                initialDelaySeconds = 90
                periodSeconds       = 15
                failureThreshold    = 3
              }
              startupProbe = {
                httpGet             = { path = "/health", port = "http" }
                initialDelaySeconds = 60
                periodSeconds       = 10
                failureThreshold    = 30
              }
            }
          ]
        }
      }
    }
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# Service — ClusterIP on port 8000
# ---------------------------------------------------------------------------------------------------------------------

resource "kubernetes_manifest" "service" {
  depends_on = [kubernetes_manifest.namespace]

  manifest = {
    apiVersion = "v1"
    kind       = "Service"
    metadata = {
      name      = "vllm"
      namespace = var.namespace
      labels    = local.common_labels
      annotations = {
        "prometheus.io/scrape" = "true"
        "prometheus.io/port"   = "8000"
        "prometheus.io/path"   = "/metrics"
      }
    }
    spec = {
      type = "ClusterIP"
      selector = {
        "app.kubernetes.io/name"      = "vllm"
        "app.kubernetes.io/component" = "inference-server"
      }
      ports = [
        {
          name       = "http"
          port       = 8000
          targetPort = "http"
          protocol   = "TCP"
        }
      ]
      sessionAffinity = "None"
    }
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# VMServiceScrape — VictoriaMetrics scrape config for vLLM metrics
# ---------------------------------------------------------------------------------------------------------------------

resource "kubernetes_manifest" "vm_service_scrape" {
  depends_on = [kubernetes_manifest.namespace]

  manifest = {
    apiVersion = "operator.victoriametrics.com/v1beta1"
    kind       = "VMServiceScrape"
    metadata = {
      name      = "vllm"
      namespace = var.namespace
      labels    = local.common_labels
    }
    spec = {
      selector = {
        matchLabels = {
          "app.kubernetes.io/name"      = "vllm"
          "app.kubernetes.io/component" = "inference-server"
        }
      }
      endpoints = [
        {
          port     = "http"
          path     = "/metrics"
          interval = "15s"
          metricRelabelConfigs = [
            {
              # Keep only vllm-prefixed metrics and standard process/python metrics
              sourceLabels = ["__name__"]
              regex        = "vllm:.+|process_.+|python_.+"
              action       = "keep"
            }
          ]
        }
      ]
      namespaceSelector = {
        matchNames = [var.namespace]
      }
    }
  }
}
