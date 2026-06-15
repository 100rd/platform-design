# ---------------------------------------------------------------------------------------------------------------------
# aws-eks-efa-fabric — EFA exposure, per-provisioner (ADR-0045 D2/D3/D4)
# ---------------------------------------------------------------------------------------------------------------------
# Encapsulates the EFA fabric plumbing so node pools stay thin (mirrors the GKE
# gke-gpu-fabric / gke-gpu-dranet split, folded into one module with a `mode` switch):
#   * mode = "device-plugin" → aws-efa-k8s-device-plugin DaemonSet (Karpenter, D2).
#   * mode = "dra"           → EFA DRA driver + a netdev DeviceClass/ResourceClaimTemplate
#                              (managed node groups only, D3) that composes with the
#                              GPU ResourceClaim from aws-eks-gpu-scheduling.
#
# Load-bearing constraint (ADR-0045): mode = "dra" is valid ONLY on managed node
# groups. A precondition asserts this so a wrong provisioner/mode pairing fails the
# plan, not the cluster (ADR-0045 Risks / ADR-0046 CI check).
#
# Default-OFF (var.enabled). ADR-0028 labels (dotted keys, platform.system=ml-platform).
# ---------------------------------------------------------------------------------------------------------------------

locals {
  platform_labels = merge(
    {
      "platform.system"     = "ml-platform"
      "platform.component"  = "gpu-fabric"
      "platform.managed-by" = "terragrunt"
    },
    var.platform_labels,
  )

  use_device_plugin = var.enabled && var.mode == "device-plugin"
  use_dra           = var.enabled && var.mode == "dra"
}

# ---------------------------------------------------------------------------------------------------------------------
# Guard: the EFA DRA driver is NOT supported under Karpenter (ADR-0045 D2/D3) — assert
# mode = "dra" only pairs with a managed node group.
# ---------------------------------------------------------------------------------------------------------------------

resource "terraform_data" "provisioner_guard" {
  count = var.enabled ? 1 : 0

  lifecycle {
    precondition {
      condition     = !(var.mode == "dra" && var.provisioner == "karpenter")
      error_message = "EFA mode 'dra' is unsupported under Karpenter (ADR-0045 D2/D3). Use mode 'device-plugin' for Karpenter pools, or 'managed-node-group' for the DRA path."
    }
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# OFI-NCCL config — env for NCCL workloads (FI_PROVIDER=efa). Shared by both modes.
# ---------------------------------------------------------------------------------------------------------------------

resource "kubernetes_config_map" "ofi_nccl" {
  count = var.enabled ? 1 : 0

  metadata {
    name      = "efa-ofi-nccl"
    namespace = var.namespace
    labels    = local.platform_labels
  }

  data = var.ofi_nccl_config
}

# ---------------------------------------------------------------------------------------------------------------------
# DEVICE-PLUGIN MODE (D2) — aws-efa-k8s-device-plugin DaemonSet (vpc.amazonaws.com/efa).
# ---------------------------------------------------------------------------------------------------------------------

resource "helm_release" "efa_device_plugin" {
  count = local.use_device_plugin ? 1 : 0

  name       = "aws-efa-k8s-device-plugin"
  repository = var.efa_device_plugin_repository
  chart      = "aws-efa-k8s-device-plugin"
  version    = var.efa_device_plugin_version
  namespace  = var.namespace
  timeout    = var.helm_timeout

  values = [
    yamlencode({
      nodeSelector = var.gpu_node_selector
      tolerations = [
        {
          key      = "nvidia.com/gpu"
          operator = "Exists"
          effect   = "NoSchedule"
        }
      ]
      podLabels = local.platform_labels
    })
  ]
}

# ---------------------------------------------------------------------------------------------------------------------
# DRA MODE (D3) — netdev DeviceClass + ResourceClaimTemplate for EFA NICs.
# Cluster-scoped DeviceClass; namespaced ResourceClaimTemplate.
# ---------------------------------------------------------------------------------------------------------------------

resource "kubernetes_manifest" "efa_device_class" {
  count = local.use_dra ? 1 : 0

  manifest = {
    apiVersion = "resource.k8s.io/v1"
    kind       = "DeviceClass"
    metadata = {
      name   = var.device_class_name
      labels = local.platform_labels
    }
    spec = {
      selectors = [
        {
          cel = {
            expression = "device.driver == \"efa.amazonaws.com\""
          }
        }
      ]
    }
  }
}

resource "kubernetes_manifest" "efa_claim_template" {
  count = local.use_dra ? 1 : 0

  manifest = {
    apiVersion = "resource.k8s.io/v1"
    kind       = "ResourceClaimTemplate"
    metadata = {
      name      = var.claim_template_name
      namespace = var.dra_namespace
      labels    = local.platform_labels
    }
    spec = {
      spec = {
        devices = {
          requests = [
            {
              name            = "efa"
              deviceClassName = var.device_class_name
              allocationMode  = "All"
            }
          ]
        }
      }
    }
  }

  depends_on = [kubernetes_manifest.efa_device_class]
}
