# ---------------------------------------------------------------------------------------------------------------------
# GKE GPUDirect-TCPX/TCPXO fabric for H100 / H100-Mega (ADR-0042 D2)
# ---------------------------------------------------------------------------------------------------------------------
# Wires the *legacy* GKE multi-networking path required for GPUDirect on a3-highgpu-8g
# (TCPX, 4 data-plane NICs) and a3-megagpu-8g (TCPXO, 8 data-plane NICs) — DRANET GA does
# NOT cover these families, so this is the only path for H100 today.
#
# Per data-plane VPC it creates:
#   * GKENetworkParamSet (deviceMode = NetDevice) referencing the VPC + subnet.
#   * Network (type Device) referencing the param set — this is what the pod's
#     additional NIC binds to.
# Plus a single NCCL plugin installer DaemonSet (TCPX or TCPXO image) that places the
# GPUDirect transport on the GPU nodes.
#
# The GKE CRDs (GKENetworkParamSet/Network) are kubernetes_manifest; the tftest mocks the
# providers so plan/validate needs no live cluster.
#
# ADR-0028: objects carry the Kubernetes-plane platform labels (dotted keys).
# ---------------------------------------------------------------------------------------------------------------------

locals {
  dp_networks = { for n in var.data_plane_networks : n.name => n }

  nccl_installer_image = var.mode == "tcpxo" ? var.tcpxo_installer_image : var.tcpx_installer_image

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
# GKENetworkParamSet — one per data-plane VPC (NetDevice mode for GPUDirect).
# ---------------------------------------------------------------------------------------------------------------------

resource "kubernetes_manifest" "param_set" {
  for_each = var.enabled ? local.dp_networks : {}

  manifest = {
    apiVersion = "networking.gke.io/v1"
    kind       = "GKENetworkParamSet"
    metadata = {
      name   = each.value.name
      labels = local.platform_labels
    }
    spec = {
      vpc        = each.value.network
      vpcSubnet  = each.value.subnetwork
      deviceMode = "NetDevice"
    }
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# Network — the Device-type network the pod's additional NIC attaches to.
# ---------------------------------------------------------------------------------------------------------------------

resource "kubernetes_manifest" "network" {
  for_each = var.enabled ? local.dp_networks : {}

  manifest = {
    apiVersion = "networking.gke.io/v1"
    kind       = "Network"
    metadata = {
      name   = each.value.name
      labels = local.platform_labels
    }
    spec = {
      type = "Device"
      parametersRef = {
        group = "networking.gke.io"
        kind  = "GKENetworkParamSet"
        name  = each.value.name
      }
    }
  }

  depends_on = [kubernetes_manifest.param_set]
}

# ---------------------------------------------------------------------------------------------------------------------
# NCCL plugin installer DaemonSet — installs the GPUDirect-TCPX/TCPXO transport on nodes.
# ---------------------------------------------------------------------------------------------------------------------

resource "kubernetes_manifest" "nccl_installer" {
  count = var.enabled ? 1 : 0

  manifest = {
    apiVersion = "apps/v1"
    kind       = "DaemonSet"
    metadata = {
      name      = "nccl-${var.mode}-installer"
      namespace = var.namespace
      labels    = local.platform_labels
    }
    spec = {
      selector = {
        matchLabels = { app = "nccl-${var.mode}-installer" }
      }
      template = {
        metadata = {
          labels = merge(local.platform_labels, { app = "nccl-${var.mode}-installer" })
        }
        spec = {
          # Only land on pools tagged with this fabric mode (set by gcp-gke-gpu-nodepools).
          nodeSelector = { "fabric-mode" = var.mode }
          tolerations = [
            { key = "nvidia.com/gpu", operator = "Exists", effect = "NoSchedule" }
          ]
          hostPID = true
          volumes = [
            { name = "var-lib", hostPath = { path = "/var/lib" } }
          ]
          initContainers = [
            {
              name            = "installer"
              image           = local.nccl_installer_image
              securityContext = { privileged = true }
              volumeMounts    = [{ name = "var-lib", mountPath = "/var/lib" }]
            }
          ]
          containers = [
            {
              name    = "pause"
              image   = var.pause_image
              command = ["/bin/sh", "-c", "sleep infinity"]
            }
          ]
        }
      }
    }
  }
}
