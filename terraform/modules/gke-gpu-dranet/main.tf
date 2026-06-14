# ---------------------------------------------------------------------------------------------------------------------
# GKE managed DRANET — RoCE RDMA fabric via Dynamic Resource Allocation (ADR-0042 D3)
# ---------------------------------------------------------------------------------------------------------------------
# Ships the DRA `netdev` objects for GPUDirect-RDMA / RoCE on H200 / B200
# (a3-ultragpu-8g, a4-highgpu-8g):
#
#   * DeviceClass        — selects the DRANET-managed RDMA NICs (driver dra.net).
#   * ResourceClaimTemplate — binds those NICs to a pod, alongside the GPU-compute
#                          ResourceClaim from ADR-0036 (one DRA model for GPU + NIC).
#
# Prerequisites (NOT created here — they are cluster/VPC concerns):
#   * GKE managed DRANET enabled on the cluster (GKE >= 1.35.2-gke.1842000).
#   * A RoCE VPC (gcp-gpu-vpc enable_rdma_network) attached to the A3-Ultra/A4 pools.
#
# Like gpu-inference-dra, the DRA objects are kubernetes_manifest resources; the tftest
# mocks the kubernetes provider so plan/validate needs no live cluster.
#
# ADR-0028: objects carry the Kubernetes-plane platform labels (dotted keys).
# ---------------------------------------------------------------------------------------------------------------------

locals {
  platform_labels = merge(
    {
      "platform.system"     = "ml-infra"
      "platform.component"  = "gpu-fabric"
      "platform.managed-by" = "terragrunt"
    },
    var.platform_labels,
  )
}

# ---------------------------------------------------------------------------------------------------------------------
# DeviceClass — RoCE RDMA NICs managed by DRANET (driver dra.net).
# ---------------------------------------------------------------------------------------------------------------------

resource "kubernetes_manifest" "deviceclass_roce" {
  count = var.enabled ? 1 : 0

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
            # Match DRANET-managed RDMA-capable network interfaces.
            expression = "device.driver == '${var.dranet_driver}'"
          }
        }
      ]
    }
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# ResourceClaimTemplate — all RDMA NICs on the node, bound per pod.
# ---------------------------------------------------------------------------------------------------------------------

resource "kubernetes_manifest" "claimtemplate_rdma" {
  count = var.enabled ? 1 : 0

  manifest = {
    apiVersion = "resource.k8s.io/v1"
    kind       = "ResourceClaimTemplate"
    metadata = {
      name      = var.claim_template_name
      namespace = var.namespace
      labels    = local.platform_labels
    }
    spec = {
      spec = {
        devices = {
          requests = [
            {
              name            = "rdma-nics"
              deviceClassName = var.device_class_name
              # All RDMA NICs attached to the node (3.2 Tbps across 8 CX-7 on A3-Ultra/A4).
              allocationMode = "All"
            }
          ]
        }
      }
    }
  }
}
