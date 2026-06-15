# ---------------------------------------------------------------------------------------------------------------------
# Bare-metal NVIDIA GPU Operator Module (WS-A — ml-infra) — ADR-0050
# ---------------------------------------------------------------------------------------------------------------------
# Deploys the NVIDIA GPU Operator in DRIVER-LESS mode on the Talos GPU cluster.
#
# On Talos the GPU driver is delivered as a SYSTEM EXTENSION baked into the boot image
# (talos-machineconfig + ADR-0050) — it can NOT be installed by the Operator, because
# Talos has no package manager and no writable host filesystem. So unlike a cloud cluster
# the Operator runs:
#   * driver.enabled  = false   (driver ships in the Talos extension)
#   * toolkit.enabled = false   (nvidia-container-toolkit ships in the Talos extension)
#   * dcgmExporter    = false   (owned by baremetal-gpu-dcgm)
# and provides ONLY device-plugin + GFD/NFD/CDI + the NVIDIA DRA driver.
#
# This is the immutable-OS inversion of the gke-gpu-operator module (which also runs
# driver-less but because GKE/COS provides the driver). Here the reason is Talos.
#
# ADR-0028: namespace + workloads carry the Kubernetes-plane dotted labels.
# ---------------------------------------------------------------------------------------------------------------------

locals {
  platform_labels = merge(
    {
      "platform.system"     = "ml-infra"
      "platform.component"  = "compute"
      "platform.managed-by" = "terragrunt"
    },
    var.platform_labels,
  )
}

# ---------------------------------------------------------------------------------------------------------------------
# Namespace — carries ADR-0028 labels so operator workloads inherit the system boundary.
# ---------------------------------------------------------------------------------------------------------------------

resource "kubernetes_namespace" "gpu_operator" {
  count = var.enabled ? 1 : 0

  metadata {
    name   = var.namespace
    labels = local.platform_labels
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# NVIDIA GPU Operator Helm release — driver-less (driver lives in the Talos extension).
# ---------------------------------------------------------------------------------------------------------------------

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
      # ADR-0050: driver + toolkit ship in the Talos system extension — NEVER installed
      # by the Operator on an immutable host. These are hard false on bare-metal Talos.
      driver = {
        enabled = var.driver_enabled
      }
      toolkit = {
        enabled = var.toolkit_enabled
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
      # NVIDIA DRA driver for fine-grained / fractional GPU allocation.
      dra = {
        enabled = var.dra_enabled
      }
      # DCGM is owned by the dedicated baremetal-gpu-dcgm module.
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
