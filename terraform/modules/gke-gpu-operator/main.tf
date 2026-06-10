# ---------------------------------------------------------------------------------------------------------------------
# GKE GPU Operator Module (WS-A — ml-infra)
# ---------------------------------------------------------------------------------------------------------------------
# Deploys the NVIDIA GPU Operator on a GKE Standard cluster via helm_release.
#
# On GKE the COS node image already ships the container toolkit and (with the
# GKE-managed driver DaemonSet) the kernel driver, so driver_enabled / toolkit_enabled
# default to false — the operator here primarily provides device-plugin, GPU Feature
# Discovery and Node Feature Discovery. Flip the toggles for clusters that need the
# operator to own the full driver stack.
#
# The whole module is gated by var.enabled so a cluster can instead rely purely on
# the GKE-managed GPU driver DaemonSet (no operator) by setting enabled = false.
#
# ADR-0028: namespace and operator workloads carry the Kubernetes-plane platform
# labels (dotted keys, platform.system = ml-infra). K8s label keys use dots, unlike
# the GCP-plane underscore spelling used by GCP resource labels.
# ---------------------------------------------------------------------------------------------------------------------

locals {
  # ADR-0028 Kubernetes-plane baseline labels for the ml-infra system.
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
# Namespace — carries the ADR-0028 labels so all operator workloads inherit the system boundary.
# ---------------------------------------------------------------------------------------------------------------------

resource "kubernetes_namespace" "gpu_operator" {
  count = var.enabled ? 1 : 0

  metadata {
    name   = var.namespace
    labels = local.platform_labels
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# NVIDIA GPU Operator Helm release.
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
      # GKE-managed driver/toolkit by default — operator just runs plugin + discovery.
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
      # DCGM is owned by the dedicated gke-gpu-dcgm module.
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
        # ADR-0028 labels propagated onto operator-managed pods.
        labels = local.platform_labels
      }
    })
  ]
}
