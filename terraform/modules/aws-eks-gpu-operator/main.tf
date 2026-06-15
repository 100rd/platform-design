# ---------------------------------------------------------------------------------------------------------------------
# aws-eks-gpu-operator — NVIDIA GPU Operator on EKS (ADR-0044 D1)
# ---------------------------------------------------------------------------------------------------------------------
# Mirrors gke-gpu-operator with the AWS/Bottlerocket deltas:
#   * driver_enabled is FALSE on Bottlerocket (driver pre-baked in the GPU AMI) and
#     TRUE on AL2023 (operator installs it) — the inverse of GKE's COS case (D1).
#   * the NVIDIA DRA driver is enabled (publishes ResourceSlices for typed GPU
#     requests, ADR-0044 D2) — the reason to run the operator over the plain plugin.
#   * the bundled DCGM exporter is disabled — DCGM is owned by aws-eks-gpu-dcgm.
#
# Default-OFF (var.enabled). Providers (helm/kubernetes) are EKS-authenticated by the
# catalog unit via the `aws eks get-token` exec pattern; mocked in tests.
#
# ADR-0028: namespace + operator workloads carry the Kubernetes-plane platform labels
# (dotted keys, platform.system = ml-platform).
# ---------------------------------------------------------------------------------------------------------------------

locals {
  # Derive the driver toggle from node_os unless explicitly overridden (D1).
  driver_enabled = var.driver_enabled != null ? var.driver_enabled : (var.node_os == "al2023")

  platform_labels = merge(
    {
      "platform.system"     = "ml-platform"
      "platform.component"  = "gpu-operator"
      "platform.managed-by" = "terragrunt"
    },
    var.platform_labels,
  )
}

resource "kubernetes_namespace" "gpu_operator" {
  count = var.enabled ? 1 : 0

  metadata {
    name   = var.namespace
    labels = local.platform_labels
  }
}

resource "helm_release" "gpu_operator" {
  count = var.enabled ? 1 : 0

  name       = "gpu-operator"
  repository = var.chart_repository
  chart      = "gpu-operator"
  version    = var.chart_version
  namespace  = kubernetes_namespace.gpu_operator[0].metadata[0].name
  timeout    = var.helm_timeout

  values = [
    yamlencode({
      # Driver: pre-baked on Bottlerocket (false), operator-installed on AL2023 (true).
      driver = {
        enabled = local.driver_enabled
      }
      toolkit = {
        # Bottlerocket bakes the toolkit; AL2023 GPU AMI also ships it — operator
        # does not need to manage it on either EKS GPU AMI variant.
        enabled = false
      }
      devicePlugin = {
        enabled = true
      }
      gfd = {
        enabled = true
      }
      nfd = {
        enabled = true
      }
      cdi = {
        enabled = true
      }
      # NVIDIA DRA driver — typed GPU ResourceSlices (ADR-0044 D2).
      nvidiaDriverCRD = {
        deployDefaultDriver = local.driver_enabled
      }
      draDriver = {
        enabled = var.dra_driver_enabled
      }
      # DCGM owned by aws-eks-gpu-dcgm.
      dcgmExporter = {
        enabled = var.dcgm_exporter_enabled
      }
      operator = {
        nodeSelector = var.gpu_node_selector
        tolerations = [
          {
            key      = "nvidia.com/gpu"
            operator = "Exists"
            effect   = "NoSchedule"
          }
        ]
        resources = {
          limits = {
            cpu    = var.operator_cpu_limit
            memory = var.operator_memory_limit
          }
        }
        labels = local.platform_labels
      }
    })
  ]
}
