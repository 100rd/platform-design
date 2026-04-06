# ---------------------------------------------------------------------------------------------------------------------
# GPU Inference DRA DeviceClass Definitions
# ---------------------------------------------------------------------------------------------------------------------
# Deploys Kubernetes DeviceClass and ResourceClaimTemplate resources for
# DRA-based GPU allocation. DeviceClasses define CEL selectors for GPU types
# using the NVIDIA DRA driver, and ResourceClaimTemplates provide reusable
# allocation patterns for common workload shapes.
#
# DeviceClasses:
#   - nvidia-h100-sxm5  — H100 SXM5 GPUs (p5.48xlarge)
#   - nvidia-a100-80gb  — A100 80GB GPUs (p4d.24xlarge)
#
# ResourceClaimTemplates:
#   - single-gpu-inference    — 1x H100 for inference workloads
#   - full-node-training      — 8x H100 (full NVLink island) for training
#   - prioritized-gpu-inference — H100 preferred, A100 fallback
# ---------------------------------------------------------------------------------------------------------------------

resource "kubernetes_manifest" "deviceclass_h100" {
  manifest = {
    apiVersion = "resource.k8s.io/v1"
    kind       = "DeviceClass"
    metadata = {
      name = "nvidia-h100-sxm5"
      labels = {
        "gpu-type"   = "H100-SXM5"
        "managed-by" = "gpu-inference"
      }
    }
    spec = {
      selectors = [
        {
          cel = {
            expression = "device.driver == 'gpu.nvidia.com' && device.attributes['gpu.nvidia.com'].productName == 'H100-SXM5'"
          }
        }
      ]
    }
  }
}

resource "kubernetes_manifest" "deviceclass_a100" {
  manifest = {
    apiVersion = "resource.k8s.io/v1"
    kind       = "DeviceClass"
    metadata = {
      name = "nvidia-a100-80gb"
      labels = {
        "gpu-type"   = "A100-80GB"
        "managed-by" = "gpu-inference"
      }
    }
    spec = {
      selectors = [
        {
          cel = {
            expression = "device.driver == 'gpu.nvidia.com' && device.attributes['gpu.nvidia.com'].productName == 'A100-SXM4-80GB'"
          }
        }
      ]
    }
  }
}

resource "kubernetes_manifest" "claimtemplate_single_gpu" {
  manifest = {
    apiVersion = "resource.k8s.io/v1"
    kind       = "ResourceClaimTemplate"
    metadata = {
      name = "single-gpu-inference"
      labels = {
        "workload-type" = "inference"
        "managed-by"    = "gpu-inference"
      }
    }
    spec = {
      spec = {
        devices = {
          requests = [
            {
              name            = "gpu"
              deviceClassName = "nvidia-h100-sxm5"
              count           = 1
            }
          ]
        }
      }
    }
  }

  depends_on = [kubernetes_manifest.deviceclass_h100]
}

resource "kubernetes_manifest" "claimtemplate_full_node" {
  manifest = {
    apiVersion = "resource.k8s.io/v1"
    kind       = "ResourceClaimTemplate"
    metadata = {
      name = "full-node-training"
      labels = {
        "workload-type" = "training"
        "managed-by"    = "gpu-inference"
      }
    }
    spec = {
      spec = {
        devices = {
          requests = [
            {
              name            = "gpus"
              deviceClassName = "nvidia-h100-sxm5"
              count           = 8
              allocationMode  = "ExactCount"
            }
          ]
        }
      }
    }
  }

  depends_on = [kubernetes_manifest.deviceclass_h100]
}

resource "kubernetes_manifest" "claimtemplate_prioritized" {
  manifest = {
    apiVersion = "resource.k8s.io/v1"
    kind       = "ResourceClaimTemplate"
    metadata = {
      name = "prioritized-gpu-inference"
      labels = {
        "workload-type" = "inference"
        "managed-by"    = "gpu-inference"
      }
    }
    spec = {
      spec = {
        devices = {
          requests = [
            {
              name = "gpu"
              firstAvailable = [
                { deviceClassName = "nvidia-h100-sxm5" },
                { deviceClassName = "nvidia-a100-80gb" }
              ]
            }
          ]
        }
      }
    }
  }

  depends_on = [
    kubernetes_manifest.deviceclass_h100,
    kubernetes_manifest.deviceclass_a100,
  ]
}
