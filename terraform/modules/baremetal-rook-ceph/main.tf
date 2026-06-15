# ---------------------------------------------------------------------------------------------------------------------
# Bare-metal Rook-Ceph Storage Module (WS-A — ml-infra) — ADR-0052
# ---------------------------------------------------------------------------------------------------------------------
# Deploys Rook-Ceph as the default storage substrate: replicated block (RBD), shared FS,
# and an RGW S3 object store — all self-contained as pods (no host packages, required by
# immutable Talos). The Ceph-RGW S3 endpoint is the optional S3-compatible artifact-store
# backend for WS-B.
#
# HARD PREREQUISITE (ADR-0052): RBD PVCs will not mount until talos-machineconfig declares
# the `rbd` + `ceph` kernel modules (+ Rook kubelet extra-mounts). Without them
# csi-rbdplugin crash-loops. This module surfaces that contract via var.ceph_kernel_modules
# (wired from the talos-machineconfig output through the stack dependency) and a validation
# block that fails the plan if rbd/ceph are absent — so the load-bearing dependency is
# enforced in code, not just documented.
#
# The Rook operator install is a helm_release; the CephCluster / CephBlockPool /
# CephFilesystem / CephObjectStore CRs are kubernetes_manifest (mocked in tftest).
#
# ADR-0028: namespace + operator + every CR carry the dotted labels.
# ---------------------------------------------------------------------------------------------------------------------

locals {
  platform_labels = merge(
    {
      "platform.system"     = "ml-infra"
      "platform.component"  = "storage"
      "platform.managed-by" = "terragrunt"
    },
    var.platform_labels,
  )

  deploy_object_store = var.enabled && var.enable_object_store
}

# ---------------------------------------------------------------------------------------------------------------------
# Namespace — labeled per ADR-0028.
# ---------------------------------------------------------------------------------------------------------------------

resource "kubernetes_namespace" "rook_ceph" {
  count = var.enabled ? 1 : 0

  metadata {
    name   = var.namespace
    labels = local.platform_labels
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# Rook-Ceph operator — self-contained CSI/operator pods (no host packages, immutable Talos).
# ---------------------------------------------------------------------------------------------------------------------

resource "helm_release" "rook_ceph_operator" {
  count = var.enabled ? 1 : 0

  name       = "rook-ceph"
  repository = var.chart_repository
  chart      = "rook-ceph"
  version    = var.chart_version
  namespace  = kubernetes_namespace.rook_ceph[0].metadata[0].name
  timeout    = var.helm_timeout

  values = [
    yamlencode({
      csi = {
        enableRbdDriver    = true
        enableCephfsDriver = var.enable_filesystem
      }
      operatorPodLabels = local.platform_labels
    })
  ]
}

# ---------------------------------------------------------------------------------------------------------------------
# CephCluster — the cluster itself; replicated across nodes (≥3 mons).
# ---------------------------------------------------------------------------------------------------------------------

resource "kubernetes_manifest" "ceph_cluster" {
  count = var.enabled ? 1 : 0

  manifest = {
    apiVersion = "ceph.rook.io/v1"
    kind       = "CephCluster"
    metadata = {
      name      = "rook-ceph"
      namespace = var.namespace
      labels    = local.platform_labels
    }
    spec = {
      cephVersion = {
        image = var.ceph_image
      }
      dataDirHostPath = var.data_dir_host_path
      mon = {
        count                = var.mon_count
        allowMultiplePerNode = false
      }
      storage = {
        useAllNodes   = var.use_all_nodes
        useAllDevices = var.use_all_devices
      }
    }
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# CephBlockPool — replicated RBD pool for PVCs (Postgres/MLflow state).
# ---------------------------------------------------------------------------------------------------------------------

resource "kubernetes_manifest" "ceph_block_pool" {
  count = var.enabled ? 1 : 0

  manifest = {
    apiVersion = "ceph.rook.io/v1"
    kind       = "CephBlockPool"
    metadata = {
      name      = "replicapool"
      namespace = var.namespace
      labels    = local.platform_labels
    }
    spec = {
      failureDomain = "host"
      replicated = {
        size = var.block_pool_replicas
      }
    }
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# CephFilesystem — shared FS (RWX) for datasets. Gated by enable_filesystem.
# ---------------------------------------------------------------------------------------------------------------------

resource "kubernetes_manifest" "ceph_filesystem" {
  count = var.enabled && var.enable_filesystem ? 1 : 0

  manifest = {
    apiVersion = "ceph.rook.io/v1"
    kind       = "CephFilesystem"
    metadata = {
      name      = "ml-fs"
      namespace = var.namespace
      labels    = local.platform_labels
    }
    spec = {
      metadataPool = {
        replicated = { size = var.block_pool_replicas }
      }
      dataPools = [
        {
          name       = "default"
          replicated = { size = var.block_pool_replicas }
        }
      ]
    }
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# CephObjectStore — RGW S3 endpoint (the optional S3 artifact-store backend for WS-B).
# Gated by enable_object_store.
# ---------------------------------------------------------------------------------------------------------------------

resource "kubernetes_manifest" "ceph_object_store" {
  count = local.deploy_object_store ? 1 : 0

  manifest = {
    apiVersion = "ceph.rook.io/v1"
    kind       = "CephObjectStore"
    metadata = {
      name      = var.object_store_name
      namespace = var.namespace
      labels    = local.platform_labels
    }
    spec = {
      metadataPool = {
        replicated = { size = var.block_pool_replicas }
      }
      dataPool = {
        replicated = { size = var.block_pool_replicas }
      }
      gateway = {
        port      = var.rgw_port
        instances = var.rgw_instances
      }
    }
  }
}
