# ---------------------------------------------------------------------------------------------------------------------
# GPU Inference Scheduling Policies
# ---------------------------------------------------------------------------------------------------------------------
# Establishes Kubernetes scheduling primitives for the gpu-inference cluster:
#
#   PriorityClasses (4 tiers):
#     - gpu-system-critical   (1000000) — system-level GPU controllers / operators
#     - gpu-training-high     (var)     — distributed training jobs (Volcano / PyTorch DDP)
#     - gpu-inference-medium  (var)     — real-time inference workloads (vLLM, Triton)
#     - gpu-batch-low         (var)     — offline / batch scoring jobs
#
#   Gang scheduling:
#     - Volcano PodGroup "distributed-training-example" — 8-pod gang for training demos
#
#   ResourceQuotas:
#     - Per-namespace GPU/CPU/memory quotas (optional, toggled by var.enable_resource_quotas)
#
# The module uses kubernetes_manifest for CRDs (PodGroup) and native kubernetes provider
# resources for PriorityClass and ResourceQuota.
# ---------------------------------------------------------------------------------------------------------------------

# ── PriorityClass: gpu-system-critical ──────────────────────────────────────
resource "kubernetes_priority_class_v1" "gpu_system_critical" {
  metadata {
    name = "gpu-system-critical"
    annotations = {
      "gpu-inference/managed-by" = "terraform"
      "gpu-inference/tier"       = "system"
    }
  }

  value             = 1000000
  global_default    = false
  preemption_policy = "PreemptLowerPriority"
  description       = "Reserved for GPU system components (operators, device plugins, drivers). Do not assign to workloads."
}

# ── PriorityClass: gpu-training-high ────────────────────────────────────────
resource "kubernetes_priority_class_v1" "gpu_training_high" {
  metadata {
    name = "gpu-training-high"
    annotations = {
      "gpu-inference/managed-by" = "terraform"
      "gpu-inference/tier"       = "training"
    }
  }

  value             = var.training_priority
  global_default    = false
  preemption_policy = "PreemptLowerPriority"
  description       = "High-priority class for distributed GPU training jobs (Volcano PodGroups, PyTorch DDP, DeepSpeed)."
}

# ── PriorityClass: gpu-inference-medium ─────────────────────────────────────
resource "kubernetes_priority_class_v1" "gpu_inference_medium" {
  metadata {
    name = "gpu-inference-medium"
    annotations = {
      "gpu-inference/managed-by" = "terraform"
      "gpu-inference/tier"       = "inference"
    }
  }

  value             = var.inference_priority
  global_default    = true
  preemption_policy = "PreemptLowerPriority"
  description       = "Default priority for real-time GPU inference workloads (vLLM, Triton Inference Server)."
}

# ── PriorityClass: gpu-batch-low ────────────────────────────────────────────
resource "kubernetes_priority_class_v1" "gpu_batch_low" {
  metadata {
    name = "gpu-batch-low"
    annotations = {
      "gpu-inference/managed-by" = "terraform"
      "gpu-inference/tier"       = "batch"
    }
  }

  value             = var.batch_priority
  global_default    = false
  preemption_policy = "PreemptLowerPriority"
  description       = "Low-priority class for batch/offline GPU scoring jobs. Preemptible by training and inference."
}

# ── Gang scheduling — Volcano PodGroup example ──────────────────────────────
# Volcano PodGroup enforces gang scheduling: all `minMember` pods must be
# schedulable simultaneously before any are allowed to start. This prevents
# partial allocation dead-locks in multi-node distributed training.
resource "kubernetes_manifest" "distributed_training_podgroup" {
  manifest = {
    apiVersion = "scheduling.volcano.sh/v1beta1"
    kind       = "PodGroup"
    metadata = {
      name      = "distributed-training-example"
      namespace = "gpu-training"
      annotations = {
        "gpu-inference/managed-by"  = "terraform"
        "gpu-inference/description" = "Example 8-pod gang-scheduled PodGroup for distributed training"
      }
    }
    spec = {
      # All 8 pods must be schedulable simultaneously (gang guarantee)
      minMember = var.example_podgroup_min_member

      # Queue ties this group to a Volcano queue with binpack policy
      queue = "gpu-training-queue"

      # Priority class applied to the whole gang
      priorityClassName = kubernetes_priority_class_v1.gpu_training_high.metadata[0].name

      # Minimum aggregate resources the scheduler must reserve before starting any pod
      minResources = {
        "nvidia.com/gpu" = var.example_podgroup_min_resources_gpu
        cpu              = "64"
        memory           = "512Gi"
      }
    }
  }

  depends_on = [kubernetes_priority_class_v1.gpu_training_high]
}

# ── ResourceQuotas per namespace ─────────────────────────────────────────────
resource "kubernetes_resource_quota_v1" "gpu_namespace_quota" {
  for_each = var.enable_resource_quotas ? var.gpu_quota_namespaces : {}

  metadata {
    name      = "gpu-resource-quota"
    namespace = each.key
    annotations = {
      "gpu-inference/managed-by" = "terraform"
      "gpu-inference/tier"       = "quota"
    }
  }

  spec {
    hard = {
      "requests.nvidia.com/gpu" = each.value.requests_gpu
      "limits.nvidia.com/gpu"   = each.value.limits_gpu
      "requests.cpu"            = each.value.requests_cpu
      "limits.cpu"              = each.value.limits_cpu
      "requests.memory"         = each.value.requests_mem
      "limits.memory"           = each.value.limits_mem
    }
  }
}
