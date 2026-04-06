# ---------------------------------------------------------------------------------------------------------------------
# Volcano v1.8 Batch Scheduler with DRA Integration
# ---------------------------------------------------------------------------------------------------------------------
# Deploys Volcano batch scheduler as a secondary scheduler on the gpu-inference
# cluster. Pods opt-in via schedulerName: volcano. Includes gang scheduling,
# bin-packing, fair-share queues, and DRA plugin integration.
# ---------------------------------------------------------------------------------------------------------------------

resource "helm_release" "volcano" {
  name             = "volcano"
  repository       = "https://volcano-sh.github.io/helm-charts"
  chart            = "volcano"
  version          = var.chart_version
  namespace        = "volcano-system"
  create_namespace = true
  timeout          = 300

  values = [yamlencode({
    custom = {
      scheduler_config_override = yamlencode({
        actions = "enqueue, allocate, backfill"
        tiers = [
          {
            plugins = [
              { name = "priority" },
              { name = "gang", enablePreemptable = false },
              { name = "conformance" }
            ]
          },
          {
            plugins = [
              { name = "dra" },
              { name = "overcommit" },
              {
                name = "binpack"
                arguments = {
                  "binpack.weight"                   = 10
                  "binpack.cpu"                      = 1
                  "binpack.memory"                   = 1
                  "binpack.resources"                = "nvidia.com/gpu"
                  "binpack.resources.nvidia.com/gpu" = 10
                }
              },
              { name = "nodeorder" },
              { name = "predicates" },
              { name = "proportion" },
              { name = "topology" }
            ]
          }
        ]
      })
    }
    scheduler = {
      replicas = var.scheduler_replicas
    }
    controller = {
      replicas = var.controller_replicas
    }
  })]
}

# Queue definitions

resource "kubernetes_manifest" "queue_training" {
  depends_on = [helm_release.volcano]

  manifest = {
    apiVersion = "scheduling.volcano.sh/v1beta1"
    kind       = "Queue"
    metadata = {
      name = "training"
    }
    spec = {
      weight     = var.training_queue_weight
      capability = {}
    }
  }
}

resource "kubernetes_manifest" "queue_inference" {
  depends_on = [helm_release.volcano]

  manifest = {
    apiVersion = "scheduling.volcano.sh/v1beta1"
    kind       = "Queue"
    metadata = {
      name = "inference"
    }
    spec = {
      weight     = var.inference_queue_weight
      capability = {}
    }
  }
}

resource "kubernetes_manifest" "queue_batch" {
  depends_on = [helm_release.volcano]

  manifest = {
    apiVersion = "scheduling.volcano.sh/v1beta1"
    kind       = "Queue"
    metadata = {
      name = "batch"
    }
    spec = {
      weight     = var.batch_queue_weight
      capability = {}
    }
  }
}
