# ---------------------------------------------------------------------------------------------------------------------
# Bare-metal GPU Fabric Module (WS-A — ml-infra) — ADR-0053
# ---------------------------------------------------------------------------------------------------------------------
# High-performance GPU fabric for GPUDirect RDMA over RoCEv2 / InfiniBand (the UK doc's
# 400 Gbps IB + NVSwitch). ADR-0053 sets a two-stage maturity gate:
#
#   * DAY-0 PRIMARY:  SR-IOV / RDMA device plugin — a SriovNetworkNodePolicy carves RDMA
#                     VFs and a SriovNetwork attaches them to GPU pods. Proven, ships now.
#   * GATED TARGET:   Cilium `netdev` DRA (mirror of DRANET) — a DeviceClass +
#                     ResourceClaimTemplate selecting RDMA NICs, so Volcano schedules
#                     GPU + NIC as ONE DRA claim. Gated behind enable_dranet (the ADR-0053
#                     D3 maturity gate: GA DRA-netdev on our Talos/k8s + validated dranet
#                     release on our NIC/kernel + meets the SR-IOV NCCL baseline).
#
# Both paths target RoCEv2 or InfiniBand (var.fabric_mode) with jumbo frames (MTU 9000,
# nic-tuning). An NCCL all-reduce bandwidth test is the acceptance gate (nccl-troubleshooting.md).
#
# SR-IOV operator install is a helm_release; the SR-IOV policy/network + the DRA objects
# are kubernetes_manifest (mocked in tftest — same pattern as gke-gpu-fabric / dranet).
#
# ADR-0028: namespace + workloads + every CR carry the dotted labels.
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

  # Day-0 primary path.
  deploy_sriov = var.enabled && var.fabric_path == "sriov"
  # Gated target path (mirror of DRANET).
  deploy_dranet = var.enabled && var.enable_dranet
}

# ---------------------------------------------------------------------------------------------------------------------
# Namespace — labeled per ADR-0028.
# ---------------------------------------------------------------------------------------------------------------------

resource "kubernetes_namespace" "fabric" {
  count = var.enabled ? 1 : 0

  metadata {
    name   = var.namespace
    labels = local.platform_labels
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# SR-IOV Network Operator — the DAY-0 PRIMARY RDMA path (ADR-0053).
# ---------------------------------------------------------------------------------------------------------------------

resource "helm_release" "sriov_operator" {
  count = local.deploy_sriov ? 1 : 0

  name       = "sriov-network-operator"
  repository = var.sriov_chart_repository
  chart      = "sriov-network-operator"
  version    = var.sriov_chart_version
  namespace  = kubernetes_namespace.fabric[0].metadata[0].name
  timeout    = var.helm_timeout

  values = [
    yamlencode({
      operator = {
        nodeSelector = var.gpu_node_selector
      }
      sriovNetworkOperatorPodLabels = local.platform_labels
    })
  ]
}

# ---------------------------------------------------------------------------------------------------------------------
# SriovNetworkNodePolicy — carve RDMA VFs on the GPU NICs (RoCEv2 / IB). Day-0 primary.
# ---------------------------------------------------------------------------------------------------------------------

resource "kubernetes_manifest" "sriov_node_policy" {
  count = local.deploy_sriov ? 1 : 0

  manifest = {
    apiVersion = "sriovnetwork.openshift.io/v1"
    kind       = "SriovNetworkNodePolicy"
    metadata = {
      name      = "gpu-rdma-policy"
      namespace = var.namespace
      labels    = local.platform_labels
    }
    spec = {
      resourceName = var.sriov_resource_name
      nodeSelector = var.gpu_node_selector
      numVfs       = var.sriov_num_vfs
      isRdma       = true
      mtu          = var.mtu
      nicSelector = {
        vendor = var.sriov_nic_vendor
      }
      # IB needs the link-type set; RoCEv2 rides Ethernet.
      linkType = var.fabric_mode == "infiniband" ? "ib" : "eth"
    }
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# SriovNetwork — attach the RDMA VFs to GPU pods. Day-0 primary.
# ---------------------------------------------------------------------------------------------------------------------

resource "kubernetes_manifest" "sriov_network" {
  count = local.deploy_sriov ? 1 : 0

  manifest = {
    apiVersion = "sriovnetwork.openshift.io/v1"
    kind       = "SriovNetwork"
    metadata = {
      name      = "gpu-rdma-net"
      namespace = var.namespace
      labels    = local.platform_labels
    }
    spec = {
      resourceName     = var.sriov_resource_name
      networkNamespace = var.workload_namespace
      ipam             = jsonencode({ type = "whereabouts", range = var.rdma_ip_range })
    }
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# Cilium netdev DRA — the GATED TARGET (mirror of DRANET, ADR-0053 D3). Off by default.
# A DeviceClass selecting RDMA NICs + a ResourceClaimTemplate so GPU + NIC are ONE claim.
# ---------------------------------------------------------------------------------------------------------------------

resource "kubernetes_manifest" "dranet_device_class" {
  count = local.deploy_dranet ? 1 : 0

  manifest = {
    apiVersion = "resource.k8s.io/v1"
    kind       = "DeviceClass"
    metadata = {
      name   = var.dranet_device_class_name
      labels = local.platform_labels
    }
    spec = {
      selectors = [
        {
          cel = {
            expression = "device.driver == 'dra.net' && device.attributes['dra.net'].rdma == true"
          }
        }
      ]
    }
  }
}

resource "kubernetes_manifest" "dranet_claim_template" {
  count = local.deploy_dranet ? 1 : 0

  manifest = {
    apiVersion = "resource.k8s.io/v1"
    kind       = "ResourceClaimTemplate"
    metadata = {
      name      = "${var.dranet_device_class_name}-claim"
      namespace = var.workload_namespace
      labels    = local.platform_labels
    }
    spec = {
      spec = {
        devices = {
          requests = [
            {
              name            = "rdma-nic"
              deviceClassName = var.dranet_device_class_name
              count           = var.dranet_nic_count
            }
          ]
        }
      }
    }
  }
}
